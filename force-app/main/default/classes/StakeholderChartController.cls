public with sharing class StakeholderChartController {

    @AuraEnabled(cacheable=true)
    public static List<StakeholderNode> getOpportunityStakeholders(Id opportunityId) {
        // Input validation
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity ID is required');
        }

        List<StakeholderNode> nodes = new List<StakeholderNode>();

        try {
            List<OpportunityContactRole> roles = [
                SELECT Id, ContactId, Contact.Name, Contact.Title, Contact.Email,
                       Contact.Phone, Contact.ReportsToId, Contact.Photo_URL__c,
                       Contact.Relationship_Strength__c,
                       Role, IsPrimary
                FROM OpportunityContactRole
                WHERE OpportunityId = :opportunityId
                WITH SECURITY_ENFORCED
                ORDER BY IsPrimary DESC, Role
            ];

            for (OpportunityContactRole ocr : roles) {
                StakeholderNode node = new StakeholderNode();
                node.id = ocr.ContactId;
                node.roleId = ocr.Id;
                node.name = ocr.Contact.Name;
                node.title = ocr.Contact.Title;
                node.email = ocr.Contact.Email;
                node.phone = ocr.Contact.Phone;
                node.role = ocr.Role;
                node.isPrimary = ocr.IsPrimary;
                node.reportsToId = ocr.Contact.ReportsToId;
                node.photoUrl = ocr.Contact.Photo_URL__c;
                node.relationshipStrength = ocr.Contact.Relationship_Strength__c != null
                    ? ocr.Contact.Relationship_Strength__c.intValue() : 3;

                nodes.add(node);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading stakeholders: ' + e.getMessage());
            throw new AuraHandledException('Unable to load stakeholders');
        }

        return nodes;
    }

    @AuraEnabled(cacheable=true)
    public static AccountChartData getAccountContacts(Id accountId) {
        // Input validation
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        AccountChartData chartData = new AccountChartData();
        chartData.nodes = new List<StakeholderNode>();
        chartData.opportunities = new List<OpportunityNode>();
        chartData.cases = new List<CaseNode>();
        chartData.links = new List<ChartLink>();
        Set<Id> contactIds = new Set<Id>();
        Map<Id, Set<Id>> contactToOpportunities = new Map<Id, Set<Id>>();

        try {
            // Get Account details for the chart
            Account account = [
                SELECT Id, Name, Industry, AnnualRevenue, NumberOfEmployees,
                       Type, Rating, Website, Phone, BillingCity, BillingState,
                       BillingCountry, Owner.Name, OwnerId
                FROM Account
                WHERE Id = :accountId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // Populate account info for chart - this becomes the central node
            chartData.accountInfo = new AccountChartInfo();
            chartData.accountInfo.id = account.Id;
            chartData.accountInfo.name = account.Name;
            chartData.accountInfo.industry = account.Industry;
            chartData.accountInfo.annualRevenue = account.AnnualRevenue;
            chartData.accountInfo.numberOfEmployees = account.NumberOfEmployees;
            chartData.accountInfo.accountType = account.Type;
            chartData.accountInfo.rating = account.Rating;
            chartData.accountInfo.ownerName = account.Owner.Name;
            chartData.accountInfo.location = formatLocation(account.BillingCity, account.BillingState, account.BillingCountry);

            // Get all opportunities for this account
            List<Opportunity> opportunities = [
                SELECT Id, Name, StageName, Amount, CloseDate, Probability
                FROM Opportunity
                WHERE AccountId = :accountId
                WITH SECURITY_ENFORCED
                ORDER BY Amount DESC NULLS LAST
            ];

            Set<Id> oppIds = new Set<Id>();
            for (Opportunity opp : opportunities) {
                oppIds.add(opp.Id);

                // Create opportunity node
                OpportunityNode oppNode = new OpportunityNode();
                oppNode.id = opp.Id;
                oppNode.name = opp.Name;
                oppNode.stageName = opp.StageName;
                oppNode.amount = opp.Amount;
                oppNode.closeDate = opp.CloseDate;
                oppNode.probability = opp.Probability;
                oppNode.nodeType = 'Opportunity';
                chartData.opportunities.add(oppNode);

                // Create link from Account to Opportunity
                ChartLink accToOpp = new ChartLink();
                accToOpp.sourceId = account.Id;
                accToOpp.targetId = opp.Id;
                accToOpp.linkType = 'account-opportunity';
                chartData.links.add(accToOpp);
            }

            // Get open Cases for this account (exclude closed)
            List<Case> cases = [
                SELECT Id, CaseNumber, Subject, Status, Priority, Type, IsClosed,
                       ContactId, Contact.Name
                FROM Case
                WHERE AccountId = :accountId AND IsClosed = false
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];

            for (Case c : cases) {
                CaseNode caseNode = new CaseNode();
                caseNode.id = c.Id;
                caseNode.caseNumber = c.CaseNumber;
                caseNode.subject = c.Subject;
                caseNode.status = c.Status;
                caseNode.priority = c.Priority;
                caseNode.caseType = c.Type;
                caseNode.isClosed = c.IsClosed;
                caseNode.contactId = c.ContactId;
                caseNode.contactName = c.Contact != null ? c.Contact.Name : null;
                caseNode.nodeType = 'Case';
                chartData.cases.add(caseNode);

                // Create link from Account to Case
                ChartLink accToCase = new ChartLink();
                accToCase.sourceId = account.Id;
                accToCase.targetId = c.Id;
                accToCase.linkType = 'account-case';
                chartData.links.add(accToCase);

                // If case has a contact, create link from Case to Contact
                if (c.ContactId != null) {
                    ChartLink caseToContact = new ChartLink();
                    caseToContact.sourceId = c.Id;
                    caseToContact.targetId = c.ContactId;
                    caseToContact.linkType = 'case-contact';
                    chartData.links.add(caseToContact);
                }
            }

            // Get contacts from opportunity contact roles
            List<OpportunityContactRole> roles = [
                SELECT ContactId, Contact.Name, Contact.Title, Contact.Email,
                       Contact.Phone, Contact.ReportsToId, Contact.Photo_URL__c,
                       Role, IsPrimary, OpportunityId, Opportunity.Name
                FROM OpportunityContactRole
                WHERE OpportunityId IN :oppIds
                WITH SECURITY_ENFORCED
                ORDER BY IsPrimary DESC, Contact.Name
            ];

            for (OpportunityContactRole ocr : roles) {
                // Track which opportunities each contact is linked to
                if (!contactToOpportunities.containsKey(ocr.ContactId)) {
                    contactToOpportunities.put(ocr.ContactId, new Set<Id>());
                }
                contactToOpportunities.get(ocr.ContactId).add(ocr.OpportunityId);

                // Create link from Contact to Opportunity
                ChartLink conToOpp = new ChartLink();
                conToOpp.sourceId = ocr.ContactId;
                conToOpp.targetId = ocr.OpportunityId;
                conToOpp.linkType = 'contact-opportunity';
                conToOpp.role = ocr.Role;
                conToOpp.isPrimary = ocr.IsPrimary;
                chartData.links.add(conToOpp);

                if (!contactIds.contains(ocr.ContactId)) {
                    contactIds.add(ocr.ContactId);

                    StakeholderNode node = new StakeholderNode();
                    node.id = ocr.ContactId;
                    node.roleId = ocr.Id;
                    node.name = ocr.Contact.Name;
                    node.title = ocr.Contact.Title;
                    node.email = ocr.Contact.Email;
                    node.phone = ocr.Contact.Phone;
                    node.role = ocr.Role;
                    node.isPrimary = ocr.IsPrimary;
                    node.opportunityName = ocr.Opportunity.Name;
                    node.reportsToId = ocr.Contact.ReportsToId;
                    node.photoUrl = ocr.Contact.Photo_URL__c;
                    node.nodeType = 'Contact';
                    node.parentId = account.Id;

                    chartData.nodes.add(node);
                }
            }

            // Also get contacts directly on account who might not be on opportunities
            List<Contact> accountContacts = [
                SELECT Id, Name, Title, Email, Phone, ReportsToId, Photo_URL__c
                FROM Contact
                WHERE AccountId = :accountId AND Id NOT IN :contactIds
                WITH SECURITY_ENFORCED
                ORDER BY Name
            ];

            for (Contact con : accountContacts) {
                StakeholderNode node = new StakeholderNode();
                node.id = con.Id;
                node.name = con.Name;
                node.title = con.Title;
                node.email = con.Email;
                node.phone = con.Phone;
                node.reportsToId = con.ReportsToId;
                node.photoUrl = con.Photo_URL__c;
                node.nodeType = 'Contact';
                node.parentId = account.Id;

                chartData.nodes.add(node);

                // Create link from Account to Contact (for contacts not on opportunities)
                ChartLink accToCon = new ChartLink();
                accToCon.sourceId = account.Id;
                accToCon.targetId = con.Id;
                accToCon.linkType = 'account-contact';
                chartData.links.add(accToCon);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading contacts: ' + e.getMessage());
            throw new AuraHandledException('Unable to load contacts');
        }

        return chartData;
    }

    private static String formatLocation(String city, String state, String country) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(city)) parts.add(city);
        if (String.isNotBlank(state)) parts.add(state);
        if (String.isNotBlank(country)) parts.add(country);
        return String.join(parts, ', ');
    }


    @AuraEnabled
    public static void updateContactRelationship(Id contactId, Id reportsToId) {
        // Input validation
        if (contactId == null) {
            throw new AuraHandledException('Contact ID is required');
        }

        try {
            // CRUD check before update
            if (!Contact.sObjectType.getDescribe().isUpdateable()) {
                throw new AuraHandledException('Insufficient privileges to update contact');
            }

            Contact con = new Contact(Id = contactId);

            if (reportsToId != null) {
                con.ReportsToId = reportsToId;
            }

            SObjectAccessDecision sd = Security.stripInaccessible(AccessType.UPDATABLE, new List<Contact>{con});
            update sd.getRecords();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error updating relationship: ' + e.getMessage());
            throw new AuraHandledException('Unable to update relationship');
        }
    }

    @AuraEnabled
    public static void addContactToOpportunity(Id opportunityId, Id contactId, String role, Boolean isPrimary) {
        // Input validation
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity ID is required');
        }
        if (contactId == null) {
            throw new AuraHandledException('Contact ID is required');
        }

        try {
            List<OpportunityContactRole> existing = [
                SELECT Id FROM OpportunityContactRole
                WHERE OpportunityId = :opportunityId AND ContactId = :contactId
                WITH SECURITY_ENFORCED
            ];

            if (existing.isEmpty()) {
                // CRUD check before insert
                if (!OpportunityContactRole.sObjectType.getDescribe().isCreateable()) {
                    throw new AuraHandledException('Insufficient privileges to create opportunity contact role');
                }

                OpportunityContactRole ocr = new OpportunityContactRole(
                    OpportunityId = opportunityId,
                    ContactId = contactId,
                    Role = role,
                    IsPrimary = isPrimary != null ? isPrimary : false
                );
                SObjectAccessDecision sd = Security.stripInaccessible(AccessType.CREATABLE, new List<OpportunityContactRole>{ocr});
                insert sd.getRecords();
            } else {
                throw new AuraHandledException('Contact is already associated with this opportunity');
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error adding contact: ' + e.getMessage());
            throw new AuraHandledException('Unable to add contact to opportunity');
        }
    }

    @AuraEnabled
    public static void removeContactFromOpportunity(Id roleId) {
        // Input validation
        if (roleId == null) {
            throw new AuraHandledException('Role ID is required');
        }

        try {
            // CRUD check before delete
            if (!OpportunityContactRole.sObjectType.getDescribe().isDeletable()) {
                throw new AuraHandledException('Insufficient privileges to delete opportunity contact role');
            }

            delete new OpportunityContactRole(Id = roleId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error removing contact: ' + e.getMessage());
            throw new AuraHandledException('Unable to remove contact from opportunity');
        }
    }

    @AuraEnabled(cacheable=true)
    public static StakeholderScore calculateScore(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity ID is required');
        }

        StakeholderScore score = new StakeholderScore();

        try {
            List<OpportunityContactRole> roles = [
                SELECT Role, Contact.LastActivityDate, Contact.Relationship_Strength__c
                FROM OpportunityContactRole
                WHERE OpportunityId = :opportunityId
                WITH SECURITY_ENFORCED
            ];

            score.totalStakeholders = roles.size();
            score.hasChampion = false;
            score.hasDecisionMaker = false;
            score.hasBudgetHolder = false;

            Integer recentEngagements = 0;
            Decimal totalStrength = 0;
            Integer strengthCount = 0;
            Date thirtyDaysAgo = Date.today().addDays(-30);

            for (OpportunityContactRole ocr : roles) {
                if (ocr.Role == 'Champion') {
                    score.hasChampion = true;
                }
                if (ocr.Role == 'Decision Maker') {
                    score.hasDecisionMaker = true;
                }
                if (ocr.Role == 'Economic Buyer' || ocr.Role == 'Business User') {
                    score.hasBudgetHolder = true;
                }

                if (ocr.Contact.LastActivityDate != null &&
                    ocr.Contact.LastActivityDate >= thirtyDaysAgo) {
                    recentEngagements++;
                }

                if (ocr.Contact.Relationship_Strength__c != null) {
                    totalStrength += ocr.Contact.Relationship_Strength__c;
                    strengthCount++;
                }
            }

            // Coverage: count(20) + champion(20) + decision maker(15) + budget(15) = max 70
            Decimal coverageScore = 0;
            if (score.totalStakeholders > 0) {
                coverageScore += (score.totalStakeholders >= 3 ? 20 : score.totalStakeholders * 6.67);
            }
            if (score.hasChampion)      coverageScore += 20;
            if (score.hasDecisionMaker) coverageScore += 15;
            if (score.hasBudgetHolder)  coverageScore += 15;

            // Relationship: avg strength (1-5) mapped to 0-15 scale
            Decimal avgStrength = strengthCount > 0 ? totalStrength / strengthCount : 0;
            Decimal relationshipScore = avgStrength > 0 ? (avgStrength / 5) * 15 : 0;

            // Engagement: % of stakeholders active in last 30 days, max 15
            Decimal engagementScore = score.totalStakeholders > 0 ?
                (Decimal.valueOf(recentEngagements) / score.totalStakeholders) * 15 : 0;

            score.coverageScore     = coverageScore.intValue();
            score.relationshipScore = relationshipScore.setScale(0, System.RoundingMode.HALF_UP).intValue();
            score.engagementScore   = engagementScore.intValue();
            score.overallScore      = (coverageScore + relationshipScore + engagementScore).intValue();

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error calculating score: ' + e.getMessage());
            throw new AuraHandledException('Unable to calculate score');
        }

        return score;
    }

    @AuraEnabled(cacheable=true)
    public static OpportunityChartData getOpportunityChartData(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity ID is required');
        }

        OpportunityChartData chartData = new OpportunityChartData();
        chartData.nodes = new List<StakeholderNode>();
        chartData.cases = new List<CaseNode>();

        try {
            Opportunity opp = [
                SELECT Id, Name, StageName, Amount, CloseDate, AccountId
                FROM Opportunity WHERE Id = :opportunityId WITH SECURITY_ENFORCED LIMIT 1
            ];

            chartData.opportunityInfo = new OpportunityInfo();
            chartData.opportunityInfo.id   = opp.Id;
            chartData.opportunityInfo.name = opp.Name;
            chartData.opportunityInfo.stageName = opp.StageName;
            chartData.opportunityInfo.amount    = opp.Amount;

            Set<Id> contactIds = new Set<Id>();
            List<OpportunityContactRole> roles = [
                SELECT Id, ContactId, Contact.Name, Contact.Title, Contact.Email,
                       Contact.Phone, Contact.ReportsToId, Contact.Photo_URL__c,
                       Contact.Relationship_Strength__c, Role, IsPrimary
                FROM OpportunityContactRole
                WHERE OpportunityId = :opportunityId
                WITH SECURITY_ENFORCED
                ORDER BY IsPrimary DESC, Role
            ];

            for (OpportunityContactRole ocr : roles) {
                contactIds.add(ocr.ContactId);
                StakeholderNode node = new StakeholderNode();
                node.id          = ocr.ContactId;
                node.roleId      = ocr.Id;
                node.name        = ocr.Contact.Name;
                node.title       = ocr.Contact.Title;
                node.email       = ocr.Contact.Email;
                node.phone       = ocr.Contact.Phone;
                node.role        = ocr.Role;
                node.isPrimary   = ocr.IsPrimary;
                node.reportsToId = ocr.Contact.ReportsToId;
                node.photoUrl    = ocr.Contact.Photo_URL__c;
                node.relationshipStrength = ocr.Contact.Relationship_Strength__c != null
                    ? ocr.Contact.Relationship_Strength__c.intValue() : 3;
                chartData.nodes.add(node);
            }

            if (!contactIds.isEmpty()) {
                List<Case> cases = [
                    SELECT Id, CaseNumber, Subject, Status, Priority, IsClosed, ContactId, Contact.Name
                    FROM Case
                    WHERE AccountId = :opp.AccountId AND ContactId IN :contactIds AND IsClosed = false
                    WITH SECURITY_ENFORCED
                    ORDER BY CreatedDate DESC
                    LIMIT 50
                ];
                for (Case c : cases) {
                    CaseNode caseNode = new CaseNode();
                    caseNode.id          = c.Id;
                    caseNode.caseNumber  = c.CaseNumber;
                    caseNode.subject     = c.Subject;
                    caseNode.status      = c.Status;
                    caseNode.priority    = c.Priority;
                    caseNode.isClosed    = c.IsClosed;
                    caseNode.contactId   = c.ContactId;
                    caseNode.contactName = c.Contact != null ? c.Contact.Name : null;
                    caseNode.nodeType    = 'Case';
                    chartData.cases.add(caseNode);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading opportunity chart: ' + e.getMessage());
            throw new AuraHandledException('Unable to load opportunity chart data');
        }

        return chartData;
    }

    public class OpportunityChartData {
        @AuraEnabled public OpportunityInfo opportunityInfo;
        @AuraEnabled public List<StakeholderNode> nodes;
        @AuraEnabled public List<CaseNode> cases;
    }

    public class OpportunityInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String stageName;
        @AuraEnabled public Decimal amount;
    }

    public class AccountChartData {
        @AuraEnabled public AccountChartInfo accountInfo;
        @AuraEnabled public List<StakeholderNode> nodes;
        @AuraEnabled public List<OpportunityNode> opportunities;
        @AuraEnabled public List<CaseNode> cases;
        @AuraEnabled public List<ChartLink> links;
    }

    public class AccountChartInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String industry;
        @AuraEnabled public Decimal annualRevenue;
        @AuraEnabled public Integer numberOfEmployees;
        @AuraEnabled public String accountType;
        @AuraEnabled public String rating;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String location;
    }

    public class OpportunityNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String stageName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public Decimal probability;
        @AuraEnabled public String nodeType;
    }

    public class CaseNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public String caseType;
        @AuraEnabled public Boolean isClosed;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String nodeType;
    }

    public class ChartLink {
        @AuraEnabled public Id sourceId;
        @AuraEnabled public Id targetId;
        @AuraEnabled public String linkType;
        @AuraEnabled public String role;
        @AuraEnabled public Boolean isPrimary;
    }

    public class StakeholderNode {
        @AuraEnabled public Id id;
        @AuraEnabled public Id roleId;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String role;
        @AuraEnabled public Boolean isPrimary;
        @AuraEnabled public Boolean isTeamMember;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Id reportsToId;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public String nodeType;
        @AuraEnabled public Id parentId;
        @AuraEnabled public Integer relationshipStrength;
    }

    public class StakeholderScore {
        @AuraEnabled public Integer overallScore;
        @AuraEnabled public Integer coverageScore;
        @AuraEnabled public Integer relationshipScore;
        @AuraEnabled public Integer engagementScore;
        @AuraEnabled public Integer totalStakeholders;
        @AuraEnabled public Boolean hasChampion;
        @AuraEnabled public Boolean hasDecisionMaker;
        @AuraEnabled public Boolean hasBudgetHolder;
    }
}