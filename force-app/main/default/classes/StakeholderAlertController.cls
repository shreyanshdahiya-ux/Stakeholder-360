public with sharing class StakeholderAlertController {

    @AuraEnabled(cacheable=true)
    public static List<StakeholderAlert> getOpportunityAlerts(Id opportunityId) {
        // Input validation
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity ID is required');
        }

        List<StakeholderAlert> alerts = new List<StakeholderAlert>();

        try {
            // Get opportunity contact roles
            List<OpportunityContactRole> roles = [
                SELECT Id, ContactId, Contact.Name, Contact.Title, Contact.LastActivityDate,
                       Role, IsPrimary
                FROM OpportunityContactRole
                WHERE OpportunityId = :opportunityId
                WITH SECURITY_ENFORCED
            ];

            Date today = Date.today();
            Date thirtyDaysAgo = today.addDays(-30);
            Date sixtyDaysAgo = today.addDays(-60);

            // Check for missing key roles
            Boolean hasChampion = false;
            Boolean hasDecisionMaker = false;
            Boolean hasEconomicBuyer = false;

            for (OpportunityContactRole ocr : roles) {
                if (ocr.Role == 'Champion') hasChampion = true;
                if (ocr.Role == 'Decision Maker') hasDecisionMaker = true;
                if (ocr.Role == 'Economic Buyer') hasEconomicBuyer = true;

                // Check for inactive stakeholders
                if (ocr.Contact.LastActivityDate == null || ocr.Contact.LastActivityDate < thirtyDaysAgo) {
                    String timePeriod = ocr.Contact.LastActivityDate == null ? 'ever' :
                                       ocr.Contact.LastActivityDate < sixtyDaysAgo ? '60+ days' : '30+ days';
                    alerts.add(new StakeholderAlert(
                        'warning',
                        'Inactive Stakeholder',
                        'No engagement with ' + ocr.Contact.Name + ' for ' + timePeriod,
                        'Reach out to maintain the relationship',
                        ocr.ContactId
                    ));
                }
            }

            // Missing key roles
            if (!hasChampion) {
                alerts.add(new StakeholderAlert(
                    'error',
                    'Missing Champion',
                    'No Champion identified for this opportunity',
                    'Identify and engage an internal advocate who can champion your solution',
                    null
                ));
            }

            if (!hasDecisionMaker) {
                alerts.add(new StakeholderAlert(
                    'error',
                    'Missing Decision Maker',
                    'No Decision Maker identified',
                    'Connect with the person who has final authority on this purchase',
                    null
                ));
            }

            if (!hasEconomicBuyer) {
                alerts.add(new StakeholderAlert(
                    'warning',
                    'Missing Economic Buyer',
                    'No Economic Buyer identified',
                    'Engage with the budget holder to discuss ROI and pricing',
                    null
                ));
            }

            // Low stakeholder count
            if (roles.size() < 3) {
                alerts.add(new StakeholderAlert(
                    'warning',
                    'Limited Stakeholder Coverage',
                    'Only ' + roles.size() + ' stakeholder(s) identified',
                    'Expand your network within the account to reduce risk',
                    null
                ));
            }

            // Add success message if no alerts
            if (alerts.isEmpty()) {
                alerts.add(new StakeholderAlert(
                    'success',
                    'Stakeholder Health: Good',
                    'All key stakeholders are engaged and relationships are strong',
                    'Keep up the great work! Continue regular engagement.',
                    null
                ));
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading alerts: ' + e.getMessage());
            throw new AuraHandledException('Unable to load alerts');
        }

        return alerts;
    }

    @AuraEnabled(cacheable=true)
    public static List<StakeholderAlert> getAccountAlerts(Id accountId) {
        // Input validation
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        List<StakeholderAlert> alerts = new List<StakeholderAlert>();

        try {
            // Get contacts for this account
            List<Contact> contacts = [
                SELECT Id, Name, Title, LastActivityDate
                FROM Contact
                WHERE AccountId = :accountId
                WITH SECURITY_ENFORCED
            ];

            Date today = Date.today();
            Date thirtyDaysAgo = today.addDays(-30);

            Integer inactiveCount = 0;

            for (Contact con : contacts) {
                if (con.LastActivityDate == null || con.LastActivityDate < thirtyDaysAgo) {
                    inactiveCount++;
                }
            }

            if (contacts.isEmpty()) {
                alerts.add(new StakeholderAlert(
                    'warning',
                    'No Contacts',
                    'No contacts found for this account',
                    'Add contacts to track stakeholder relationships',
                    null
                ));
            } else {
                if (inactiveCount > 0) {
                    alerts.add(new StakeholderAlert(
                        'warning',
                        'Inactive Contacts',
                        inactiveCount + ' contact(s) with no recent activity',
                        'Review and update engagement with inactive contacts',
                        null
                    ));
                }

                if (alerts.isEmpty()) {
                    alerts.add(new StakeholderAlert(
                        'success',
                        'Account Health: Good',
                        'All contacts are active with strong relationships',
                        'Maintain regular engagement with your contacts',
                        null
                    ));
                }
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading account alerts: ' + e.getMessage());
            throw new AuraHandledException('Unable to load account alerts');
        }

        return alerts;
    }

    public class StakeholderAlert {
        @AuraEnabled public String severity;
        @AuraEnabled public String title;
        @AuraEnabled public String message;
        @AuraEnabled public String recommendation;
        @AuraEnabled public Id contactId;

        public StakeholderAlert(String severity, String title, String message, String recommendation, Id contactId) {
            this.severity = severity;
            this.title = title;
            this.message = message;
            this.recommendation = recommendation;
            this.contactId = contactId;
        }
    }
}