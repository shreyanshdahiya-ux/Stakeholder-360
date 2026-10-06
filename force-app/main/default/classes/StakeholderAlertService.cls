/**
 * Service for generating and managing stakeholder coverage alerts
 */
public with sharing class StakeholderAlertService {

    /**
     * Generate alerts for an opportunity based on stakeholder coverage
     */
    @AuraEnabled
    public static void generateAlertsForOpportunity(Id opportunityId) {
        try {
            if (!Opportunity.sObjectType.getDescribe().isAccessible()) {
                throw new AuraHandledException('Insufficient privileges to read opportunities');
            }
            // Get opportunity details
            Opportunity opp = [
                SELECT Id, Amount, StageName,
                       (SELECT Id, Role__c, Contact__c, Contact__r.Title
                        FROM Opportunity_Stakeholders__r)
                FROM Opportunity
                WHERE Id = :opportunityId
                WITH USER_MODE
                LIMIT 1
            ];

            // Delete existing open alerts
            if (!Stakeholder_Alert__c.sObjectType.getDescribe().isDeletable()) {
                throw new AuraHandledException('Insufficient privileges to delete alerts');
            }
            List<Stakeholder_Alert__c> alertsToDelete = [
                SELECT Id
                FROM Stakeholder_Alert__c
                WHERE Opportunity__c = :opportunityId
                AND Status__c = 'Active'
                WITH USER_MODE
            ];
            Database.delete(alertsToDelete, AccessLevel.USER_MODE);

            List<Stakeholder_Alert__c> newAlerts = new List<Stakeholder_Alert__c>();

            // Check for Champion
            Boolean hasChampion = checkForRole(opp.Opportunity_Stakeholders__r, 'Champion');
            if (!hasChampion && opp.Amount != null && opp.Amount > 50000) {
                newAlerts.add(createAlert(
                    opportunityId,
                    'Missing Champion',
                    'High',
                    'This opportunity has no Champion identified. Deals over $50K require a Champion.'
                ));
            }

            // Check for Decision Maker
            Boolean hasDecisionMaker = checkForRole(opp.Opportunity_Stakeholders__r, 'Decision Maker');
            if (!hasDecisionMaker && isAdvancedStage(opp.StageName)) {
                newAlerts.add(createAlert(
                    opportunityId,
                    'Missing Decision Maker',
                    'High',
                    'This opportunity is in an advanced stage but has no Decision Maker mapped.'
                ));
            }

            // Check for Budget Holder
            Boolean hasBudgetHolder = checkForRole(opp.Opportunity_Stakeholders__r, 'Budget Holder');
            if (!hasBudgetHolder && opp.Amount != null && opp.Amount > 100000) {
                newAlerts.add(createAlert(
                    opportunityId,
                    'Missing Budget Holder',
                    'Medium',
                    'This opportunity exceeds $100K but has no Budget Holder identified.'
                ));
            }

            // Check for single-threading
            if (opp.Opportunity_Stakeholders__r.size() <= 2) {
                newAlerts.add(createAlert(
                    opportunityId,
                    'Single-Threaded',
                    'Medium',
                    'This opportunity has only ' + opp.Opportunity_Stakeholders__r.size() +
                    ' stakeholder(s). Multi-threading reduces risk.'
                ));
            }

            // Check for Executive presence
            Boolean hasExecutive = checkForExecutive(opp.Opportunity_Stakeholders__r);
            if (!hasExecutive && opp.Amount != null && opp.Amount > 250000) {
                newAlerts.add(createAlert(
                    opportunityId,
                    'Missing Executive',
                    'High',
                    'This enterprise deal has no C-level or VP-level contact mapped.'
                ));
            }

            if (!newAlerts.isEmpty()) {
                if (!Stakeholder_Alert__c.sObjectType.getDescribe().isCreateable()) {
                    throw new AuraHandledException('Insufficient privileges to create alerts');
                }
                SObjectAccessDecision sd = Security.stripInaccessible(AccessType.CREATABLE, newAlerts);
                insert sd.getRecords();
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error generating alerts: ' + e.getMessage());
        }
    }

    /**
     * Get all alerts for an opportunity
     */
    @AuraEnabled(cacheable=true)
    public static List<AlertWrapper> getAlertsForOpportunity(Id opportunityId) {
        List<AlertWrapper> wrappers = new List<AlertWrapper>();

        if (!Stakeholder_Alert__c.sObjectType.getDescribe().isAccessible()) {
            throw new AuraHandledException('Insufficient privileges to read alerts');
        }
        List<Stakeholder_Alert__c> alerts = [
            SELECT Id, Alert_Type__c, Priority__c, Status__c, Message__c, CreatedDate
            FROM Stakeholder_Alert__c
            WHERE Opportunity__c = :opportunityId
            WITH USER_MODE
            ORDER BY Priority__c, CreatedDate DESC
        ];

        for (Stakeholder_Alert__c alert : alerts) {
            wrappers.add(new AlertWrapper(alert));
        }

        return wrappers;
    }

    /**
     * Update alert status
     */
    @AuraEnabled
    public static void updateAlertStatus(Id alertId, String status) {
        try {
            if (!Stakeholder_Alert__c.sObjectType.getDescribe().isUpdateable()) {
                throw new AuraHandledException('Insufficient privileges to update alert status');
            }
            Stakeholder_Alert__c alert = new Stakeholder_Alert__c(
                Id = alertId,
                Status__c = status
            );
            SObjectAccessDecision sd = Security.stripInaccessible(AccessType.UPDATABLE, new List<Stakeholder_Alert__c>{alert});
            update sd.getRecords();
        } catch (Exception e) {
            throw new AuraHandledException('Error updating alert: ' + e.getMessage());
        }
    }

    /**
     * Dismiss (resolve) an alert
     */
    @AuraEnabled
    public static void dismissAlert(Id alertId) {
        updateAlertStatus(alertId, 'Resolved');
    }

    // Helper methods
    private static Boolean checkForRole(List<Opportunity_Stakeholder__c> stakeholders, String role) {
        for (Opportunity_Stakeholder__c os : stakeholders) {
            if (os.Role__c != null && os.Role__c.contains(role)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean checkForExecutive(List<Opportunity_Stakeholder__c> stakeholders) {
        for (Opportunity_Stakeholder__c os : stakeholders) {
            String title = os.Contact__r.Title;
            if (title != null) {
                title = title.toLowerCase();
                if (title.contains('ceo') || title.contains('cto') || title.contains('cfo') ||
                    title.contains('coo') || title.contains('chief') || title.contains('vp') ||
                    title.contains('vice president')) {
                    return true;
                }
            }
        }
        return false;
    }

    private static Boolean isAdvancedStage(String stageName) {
        if (stageName == null) return false;

        Set<String> advancedStages = new Set<String>{
            'Proposal', 'Negotiation', 'Closed Won', 'Closed Lost'
        };

        return advancedStages.contains(stageName);
    }

    private static Stakeholder_Alert__c createAlert(Id oppId, String alertType,
                                                     String priority, String message) {
        return new Stakeholder_Alert__c(
            Opportunity__c = oppId,
            Alert_Type__c = alertType,
            Title__c = alertType,
            Priority__c = priority,
            Status__c = 'Active',
            Message__c = message
        );
    }

    // Wrapper class
    public class AlertWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String alertType;
        @AuraEnabled public String priority;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public DateTime createdDate;

        public AlertWrapper(Stakeholder_Alert__c alert) {
            this.id = alert.Id;
            this.alertType = alert.Alert_Type__c;
            this.priority = alert.Priority__c;
            this.status = alert.Status__c;
            this.message = alert.Message__c;
            this.createdDate = alert.CreatedDate;
        }
    }
}