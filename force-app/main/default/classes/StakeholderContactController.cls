public with sharing class StakeholderContactController {

    @AuraEnabled(cacheable=true)
    public static ContactProfile getContactProfile(Id contactId) {
        // Input validation
        if (contactId == null) {
            throw new AuraHandledException('Contact ID is required');
        }

        ContactProfile profile = new ContactProfile();

        try {
            // Get contact details
            Contact con = [
                SELECT Id, Name, Title, Email, Phone, AccountId, Account.Name,
                       LastActivityDate, Reports_To_Contact__c,
                       Reports_To_Contact__r.Name, Description, Photo_URL__c
                FROM Contact
                WHERE Id = :contactId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            profile.id = con.Id;
            profile.name = con.Name;
            profile.title = con.Title;
            profile.email = con.Email;
            profile.phone = con.Phone;
            profile.accountName = con.Account?.Name;
            profile.accountId = con.AccountId;
            profile.lastActivityDate = con.LastActivityDate;
            profile.relationshipStrength = 0;
            profile.reportsToName = con.Reports_To_Contact__r?.Name;
            profile.reportsToId = con.Reports_To_Contact__c;
            profile.description = con.Description;
            profile.photoUrl = con.Photo_URL__c;

            // Get opportunities
            List<OpportunityContactRole> roles = [
                SELECT Id, OpportunityId, Opportunity.Name, Opportunity.StageName,
                       Opportunity.Amount, Opportunity.CloseDate, Role, IsPrimary
                FROM OpportunityContactRole
                WHERE ContactId = :contactId
                WITH SECURITY_ENFORCED
                ORDER BY Opportunity.CloseDate DESC
                LIMIT 20
            ];

            profile.totalOpportunities = roles.size();
            profile.primaryOpportunities = 0;
            profile.opportunities = new List<OpportunityInfo>();

            for (OpportunityContactRole ocr : roles) {
                if (ocr.IsPrimary) {
                    profile.primaryOpportunities++;
                }

                OpportunityInfo oppInfo = new OpportunityInfo();
                oppInfo.id = ocr.OpportunityId;
                oppInfo.name = ocr.Opportunity.Name;
                oppInfo.stage = ocr.Opportunity.StageName;
                oppInfo.amount = ocr.Opportunity.Amount;
                oppInfo.closeDate = ocr.Opportunity.CloseDate;
                oppInfo.role = ocr.Role;
                oppInfo.isPrimary = ocr.IsPrimary;
                oppInfo.isOpen = !(ocr.Opportunity.StageName == 'Closed Won' ||
                                  ocr.Opportunity.StageName == 'Closed Lost');

                profile.opportunities.add(oppInfo);
            }

            // Get direct reports
            List<Contact> directReports = [
                SELECT Id, Name, Title
                FROM Contact
                WHERE Reports_To_Contact__c = :contactId
                WITH SECURITY_ENFORCED
                ORDER BY Name
                LIMIT 10
            ];

            profile.directReports = new List<ContactInfo>();
            for (Contact report : directReports) {
                ContactInfo info = new ContactInfo();
                info.id = report.Id;
                info.name = report.Name;
                info.title = report.Title;
                info.relationshipStrength = 0;
                profile.directReports.add(info);
            }

            // Get recent activities (Tasks and Events)
            List<Task> recentTasks = [
                SELECT Id, Subject, ActivityDate, Status, CreatedDate
                FROM Task
                WHERE WhoId = :contactId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT 5
            ];

            profile.recentActivities = new List<ActivityInfo>();
            for (Task t : recentTasks) {
                ActivityInfo activity = new ActivityInfo();
                activity.id = t.Id;
                activity.subject = t.Subject;
                activity.activityDate = t.ActivityDate;
                activity.status = t.Status;
                activity.type = 'Task';
                profile.recentActivities.add(activity);
            }

            // Calculate engagement score
            Integer engagementScore = 0;

            // Recent activity (70 points)
            Date thirtyDaysAgo = Date.today().addDays(-30);
            if (profile.lastActivityDate != null && profile.lastActivityDate >= thirtyDaysAgo) {
                engagementScore += 70;
            } else if (profile.lastActivityDate != null && profile.lastActivityDate >= Date.today().addDays(-60)) {
                engagementScore += 35;
            }

            // Opportunity involvement (20 points)
            if (profile.totalOpportunities >= 5) engagementScore += 20;
            else engagementScore += profile.totalOpportunities * 4;

            // Primary contact role (10 points)
            if (profile.primaryOpportunities > 0) engagementScore += 10;

            profile.engagementScore = engagementScore;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading contact profile: ' + e.getMessage());
            throw new AuraHandledException('Unable to load contact profile');
        }

        return profile;
    }

    public class ContactProfile {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id accountId;
        @AuraEnabled public Date lastActivityDate;
        @AuraEnabled public Integer relationshipStrength;
        @AuraEnabled public String reportsToName;
        @AuraEnabled public Id reportsToId;
        @AuraEnabled public String description;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public Integer totalOpportunities;
        @AuraEnabled public Integer primaryOpportunities;
        @AuraEnabled public Integer engagementScore;
        @AuraEnabled public List<OpportunityInfo> opportunities;
        @AuraEnabled public List<ContactInfo> directReports;
        @AuraEnabled public List<ActivityInfo> recentActivities;
    }

    public class OpportunityInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String stage;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public String role;
        @AuraEnabled public Boolean isPrimary;
        @AuraEnabled public Boolean isOpen;
    }

    public class ContactInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public Integer relationshipStrength;
    }

    public class ActivityInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String subject;
        @AuraEnabled public Date activityDate;
        @AuraEnabled public String status;
        @AuraEnabled public String type;
    }
}