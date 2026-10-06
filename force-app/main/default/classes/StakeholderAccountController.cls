public with sharing class StakeholderAccountController {

    @AuraEnabled(cacheable=true)
    public static AccountSummary getAccountSummary(Id accountId) {
        // Input validation
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        AccountSummary summary = new AccountSummary();

        try {
            // Get Account details with FLS enforcement
            List<Account> accounts = [
                SELECT Id, Name, Industry, AnnualRevenue, NumberOfEmployees,
                       Type, Rating, Website, Phone, BillingCity, BillingState,
                       BillingCountry, Owner.Name, OwnerId, CreatedDate,
                       LastActivityDate, Description
                FROM Account
                WHERE Id = :accountId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (accounts.isEmpty()) {
                throw new AuraHandledException('Account not found');
            }

            Account account = accounts[0];

            // Populate account info
            summary.accountInfo = new AccountInfo();
            summary.accountInfo.id = account.Id;
            summary.accountInfo.name = account.Name;
            summary.accountInfo.industry = account.Industry;
            summary.accountInfo.annualRevenue = account.AnnualRevenue;
            summary.accountInfo.numberOfEmployees = account.NumberOfEmployees;
            summary.accountInfo.accountType = account.Type;
            summary.accountInfo.rating = account.Rating;
            summary.accountInfo.website = account.Website;
            summary.accountInfo.phone = account.Phone;
            summary.accountInfo.billingCity = account.BillingCity;
            summary.accountInfo.billingState = account.BillingState;
            summary.accountInfo.billingCountry = account.BillingCountry;
            summary.accountInfo.ownerName = account.Owner.Name;
            summary.accountInfo.ownerId = account.OwnerId;
            summary.accountInfo.createdDate = account.CreatedDate;
            summary.accountInfo.lastActivityDate = account.LastActivityDate;
            summary.accountInfo.description = account.Description;

            // Calculate account tenure in days
            if (account.CreatedDate != null) {
                summary.accountInfo.tenureDays = account.CreatedDate.date().daysBetween(Date.today());
            }

            // Calculate days since last activity
            if (account.LastActivityDate != null) {
                summary.accountInfo.daysSinceLastActivity = account.LastActivityDate.daysBetween(Date.today());
            }

            // Get actual opportunity count (no LIMIT)
            List<AggregateResult> oppCountResult = [
                SELECT COUNT(Id) cnt
                FROM Opportunity
                WHERE AccountId = :accountId
                WITH SECURITY_ENFORCED
            ];
            summary.totalOpportunities = oppCountResult.isEmpty() ? 0 : (Integer)oppCountResult[0].get('cnt');

            // Fetch recent opportunities for open/won/value calculations (capped for performance)
            List<Opportunity> opportunities = [
                SELECT Id, Name, StageName, Amount, CloseDate
                FROM Opportunity
                WHERE AccountId = :accountId
                WITH SECURITY_ENFORCED
                ORDER BY CloseDate DESC
                LIMIT 200
            ];

            summary.openOpportunities = 0;
            summary.wonOpportunities = 0;
            Decimal totalValue = 0;

            for (Opportunity opp : opportunities) {
                if (opp.Amount != null) {
                    totalValue += opp.Amount;
                }
                if (opp.StageName == 'Closed Won') {
                    summary.wonOpportunities++;
                } else if (opp.StageName != 'Closed Lost') {
                    summary.openOpportunities++;
                }
            }
            summary.totalValue = totalValue;

            // Get contacts
            Set<Id> opportunityIds = new Map<Id, Opportunity>(opportunities).keySet();

            List<Contact> contacts = [
                SELECT Id, Name, Title, Email, Phone, LastActivityDate
                FROM Contact
                WHERE AccountId = :accountId
                WITH SECURITY_ENFORCED
                ORDER BY LastActivityDate DESC NULLS LAST
            ];

            summary.totalContacts = contacts.size();
            summary.activeContacts = 0;
            Date thirtyDaysAgo = Date.today().addDays(-30);

            for (Contact con : contacts) {
                if (con.LastActivityDate != null && con.LastActivityDate >= thirtyDaysAgo) {
                    summary.activeContacts++;
                }
            }

            // Calculate average relationship strength from Stakeholder_Relationship__c
            List<Stakeholder_Relationship__c> relationships = [
                SELECT Strength__c
                FROM Stakeholder_Relationship__c
                WHERE Account__c = :accountId
                WITH SECURITY_ENFORCED
            ];

            if (!relationships.isEmpty()) {
                Decimal totalStrength = 0;
                Integer strengthCount = 0;
                for (Stakeholder_Relationship__c rel : relationships) {
                    if (rel.Strength__c != null) {
                        totalStrength += rel.Strength__c;
                        strengthCount++;
                    }
                }
                summary.averageRelationshipStrength = strengthCount > 0
                    ? (totalStrength / strengthCount).setScale(1)
                    : 0;
            } else {
                summary.averageRelationshipStrength = 0;
            }

            // Get stakeholder coverage by role with FLS enforcement
            List<OpportunityContactRole> roles = [
                SELECT Id, Role
                FROM OpportunityContactRole
                WHERE OpportunityId IN :opportunityIds
                WITH SECURITY_ENFORCED
            ];

            Map<String, Integer> roleCounts = new Map<String, Integer>();
            for (OpportunityContactRole ocr : roles) {
                if (ocr.Role != null) {
                    Integer count = roleCounts.containsKey(ocr.Role) ? roleCounts.get(ocr.Role) : 0;
                    roleCounts.put(ocr.Role, count + 1);
                }
            }

            summary.roleDistribution = new List<RoleCount>();
            for (String role : roleCounts.keySet()) {
                summary.roleDistribution.add(new RoleCount(role, roleCounts.get(role)));
            }

            // Calculate health score (now includes Account-level factors)
            Integer healthScore = 0;

            // Contact coverage score (max 25 points)
            if (summary.totalContacts >= 5) healthScore += 25;
            else healthScore += summary.totalContacts * 5;

            // Active contacts score (max 35 points)
            if (summary.activeContacts >= 5) healthScore += 35;
            else healthScore += summary.activeContacts * 7;

            // Opportunity engagement score (max 15 points)
            if (summary.openOpportunities > 0) healthScore += 15;

            // Account-level factors (max 25 points)
            // Rating factor (max 10 points)
            if (summary.accountInfo.rating == 'Hot') healthScore += 10;
            else if (summary.accountInfo.rating == 'Warm') healthScore += 6;
            else if (summary.accountInfo.rating == 'Cold') healthScore += 2;

            // Recent activity factor (max 10 points)
            if (summary.accountInfo.daysSinceLastActivity != null) {
                if (summary.accountInfo.daysSinceLastActivity <= 7) healthScore += 10;
                else if (summary.accountInfo.daysSinceLastActivity <= 14) healthScore += 7;
                else if (summary.accountInfo.daysSinceLastActivity <= 30) healthScore += 4;
            }

            // Account type factor (max 5 points)
            if (summary.accountInfo.accountType == 'Customer') healthScore += 5;
            else if (summary.accountInfo.accountType == 'Partner') healthScore += 4;
            else if (summary.accountInfo.accountType == 'Prospect') healthScore += 3;

            summary.healthScore = Math.min(healthScore, 100);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading account summary: ' + e.getMessage());
            throw new AuraHandledException('Unable to load account summary');
        }

        return summary;
    }

    @AuraEnabled(cacheable=true)
    public static List<ContactInfo> getKeyContacts(Id accountId) {
        // Input validation
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        List<ContactInfo> contacts = new List<ContactInfo>();

        try {
            List<Contact> accountContacts = [
                SELECT Id, Name, Title, Email, Phone, LastActivityDate,
                       Reports_To_Contact__c, Reports_To_Contact__r.Name, Photo_URL__c,
                       Relationship_Strength__c
                FROM Contact
                WHERE AccountId = :accountId
                WITH SECURITY_ENFORCED
                ORDER BY LastActivityDate DESC NULLS LAST
                LIMIT 20
            ];

            for (Contact con : accountContacts) {
                ContactInfo info = new ContactInfo();
                info.id = con.Id;
                info.name = con.Name;
                info.title = con.Title;
                info.email = con.Email;
                info.phone = con.Phone;
                info.lastActivityDate = con.LastActivityDate;
                info.relationshipStrength = con.Relationship_Strength__c != null
                    ? con.Relationship_Strength__c.intValue()
                    : 0;
                info.reportsToName = con.Reports_To_Contact__r?.Name;
                info.photoUrl = con.Photo_URL__c;
                info.isActive = con.LastActivityDate != null &&
                    con.LastActivityDate >= Date.today().addDays(-30);
                contacts.add(info);
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading contacts: ' + e.getMessage());
            throw new AuraHandledException('Unable to load contacts');
        }

        return contacts;
    }

    public class AccountSummary {
        @AuraEnabled public AccountInfo accountInfo;
        @AuraEnabled public Integer totalOpportunities;
        @AuraEnabled public Integer openOpportunities;
        @AuraEnabled public Integer wonOpportunities;
        @AuraEnabled public Decimal totalValue;
        @AuraEnabled public Integer totalContacts;
        @AuraEnabled public Integer activeContacts;
        @AuraEnabled public Decimal averageRelationshipStrength;
        @AuraEnabled public Integer healthScore;
        @AuraEnabled public List<RoleCount> roleDistribution;
    }

    public class AccountInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String industry;
        @AuraEnabled public Decimal annualRevenue;
        @AuraEnabled public Integer numberOfEmployees;
        @AuraEnabled public String accountType;
        @AuraEnabled public String rating;
        @AuraEnabled public String website;
        @AuraEnabled public String phone;
        @AuraEnabled public String billingCity;
        @AuraEnabled public String billingState;
        @AuraEnabled public String billingCountry;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public Date lastActivityDate;
        @AuraEnabled public String description;
        @AuraEnabled public Integer tenureDays;
        @AuraEnabled public Integer daysSinceLastActivity;
    }

    public class RoleCount {
        @AuraEnabled public String role;
        @AuraEnabled public Integer count;

        public RoleCount(String role, Integer count) {
            this.role = role;
            this.count = count;
        }
    }

    public class ContactInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public Date lastActivityDate;
        @AuraEnabled public Integer relationshipStrength;
        @AuraEnabled public String reportsToName;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public Boolean isActive;
    }
}