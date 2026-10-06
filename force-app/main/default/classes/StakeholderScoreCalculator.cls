/**
 * Service for calculating stakeholder scores at the opportunity level
 */
public with sharing class StakeholderScoreCalculator {

    // Scoring weights (must sum to 100)
    private static final Decimal WEIGHT_STAKEHOLDER_COUNT = 20;
    private static final Decimal WEIGHT_KEY_ROLES = 30;
    private static final Decimal WEIGHT_RELATIONSHIP_STRENGTH = 25;
    private static final Decimal WEIGHT_ENGAGEMENT_RECENCY = 15;
    private static final Decimal WEIGHT_BLOCKER_MITIGATION = 10;

    /**
     * Calculate and update stakeholder score for an opportunity
     */
    @AuraEnabled
    public static Decimal calculateOpportunityScore(Id opportunityId) {
        try {
            if (!Opportunity.sObjectType.getDescribe().isAccessible()) {
                throw new AuraHandledException('Insufficient privileges to read opportunities');
            }
            Opportunity opp = [
                SELECT Id,
                       (SELECT Id, Role__c, Contact__c, Contact__r.LastActivityDate,
                               Contact__r.Stakeholder_Score__c
                        FROM Opportunity_Stakeholders__r)
                FROM Opportunity
                WHERE Id = :opportunityId
                WITH USER_MODE
                LIMIT 1
            ];

            Decimal score = calculateScore(opp);

            // Update the opportunity with the calculated score
            if (!Opportunity.sObjectType.getDescribe().isUpdateable()) {
                throw new AuraHandledException('Insufficient privileges to update opportunity score');
            }
            opp.Stakeholder_Score__c = score;
            SObjectAccessDecision sd = Security.stripInaccessible(AccessType.UPDATABLE, new List<Opportunity>{opp});
            update sd.getRecords();

            return score;
        } catch (Exception e) {
            throw new AuraHandledException('Error calculating score: ' + e.getMessage());
        }
    }

    /**
     * Batch calculate scores for multiple opportunities
     */
    @AuraEnabled
    public static void calculateScoresForOpportunities(List<Id> opportunityIds) {
        List<Opportunity> oppsToUpdate = new List<Opportunity>();

        if (!Opportunity.sObjectType.getDescribe().isAccessible()) {
            throw new AuraHandledException('Insufficient privileges to read opportunities');
        }
        List<Opportunity> opps = [
            SELECT Id,
                   (SELECT Id, Role__c, Contact__c, Contact__r.LastActivityDate,
                           Contact__r.Stakeholder_Score__c
                    FROM Opportunity_Stakeholders__r)
            FROM Opportunity
            WHERE Id IN :opportunityIds
            WITH USER_MODE
        ];

        for (Opportunity opp : opps) {
            Decimal score = calculateScore(opp);
            opp.Stakeholder_Score__c = score;
            oppsToUpdate.add(opp);
        }

        if (!oppsToUpdate.isEmpty()) {
            if (!Opportunity.sObjectType.getDescribe().isUpdateable()) {
                throw new AuraHandledException('Insufficient privileges to update opportunity scores');
            }
            SObjectAccessDecision sd = Security.stripInaccessible(AccessType.UPDATABLE, oppsToUpdate);
            update sd.getRecords();
        }
    }

    /**
     * Get score breakdown for display
     */
    @AuraEnabled(cacheable=true)
    public static ScoreBreakdown getScoreBreakdown(Id opportunityId) {
        if (!Opportunity.sObjectType.getDescribe().isAccessible()) {
            throw new AuraHandledException('Insufficient privileges to read opportunities');
        }
        Opportunity opp = [
            SELECT Id,
                   (SELECT Id, Role__c, Contact__c, Contact__r.LastActivityDate,
                           Contact__r.Stakeholder_Score__c
                    FROM Opportunity_Stakeholders__r)
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        return calculateScoreBreakdown(opp);
    }

    // Private helper methods
    private static Decimal calculateScore(Opportunity opp) {
        ScoreBreakdown breakdown = calculateScoreBreakdown(opp);
        return breakdown.totalScore;
    }

    private static ScoreBreakdown calculateScoreBreakdown(Opportunity opp) {
        ScoreBreakdown breakdown = new ScoreBreakdown();

        List<Opportunity_Stakeholder__c> stakeholders = opp.Opportunity_Stakeholders__r;

        // Component 1: Number of stakeholders (20%)
        breakdown.countScore = calculateCountScore(stakeholders.size());

        // Component 2: Key roles coverage (30%)
        breakdown.rolesScore = calculateRolesScore(stakeholders);

        // Component 3: Average relationship strength (25%)
        breakdown.strengthScore = calculateStrengthScore(stakeholders);

        // Component 4: Engagement recency (15%)
        breakdown.engagementScore = calculateEngagementScore(stakeholders);

        // Component 5: Blocker mitigation (10%)
        breakdown.blockerScore = calculateBlockerScore(stakeholders);

        // Total score
        breakdown.totalScore =
            breakdown.countScore * (WEIGHT_STAKEHOLDER_COUNT / 100) +
            breakdown.rolesScore * (WEIGHT_KEY_ROLES / 100) +
            breakdown.strengthScore * (WEIGHT_RELATIONSHIP_STRENGTH / 100) +
            breakdown.engagementScore * (WEIGHT_ENGAGEMENT_RECENCY / 100) +
            breakdown.blockerScore * (WEIGHT_BLOCKER_MITIGATION / 100);

        breakdown.grade = getGrade(breakdown.totalScore);
        breakdown.status = getStatus(breakdown.totalScore);

        return breakdown;
    }

    private static Decimal calculateCountScore(Integer count) {
        if (count == 0) return 0;
        if (count >= 8) return 100;
        // Linear scale: 0 stakeholders = 0, 8+ = 100
        return (count / 8.0) * 100;
    }

    private static Decimal calculateRolesScore(List<Opportunity_Stakeholder__c> stakeholders) {
        Boolean hasChampion = false;
        Boolean hasDecisionMaker = false;
        Boolean hasBudgetHolder = false;

        for (Opportunity_Stakeholder__c os : stakeholders) {
            if (os.Role__c != null) {
                if (os.Role__c.contains('Champion')) hasChampion = true;
                if (os.Role__c.contains('Decision Maker')) hasDecisionMaker = true;
                if (os.Role__c.contains('Budget Holder')) hasBudgetHolder = true;
            }
        }

        Integer score = 0;
        if (hasChampion) score += 40;        // Champion is most critical
        if (hasDecisionMaker) score += 35;   // Decision Maker second
        if (hasBudgetHolder) score += 25;    // Budget Holder third

        return score;
    }

    private static Decimal calculateStrengthScore(List<Opportunity_Stakeholder__c> stakeholders) {
        if (stakeholders.isEmpty()) return 0;

        Decimal totalStrength = 0;
        Integer count = 0;

        for (Opportunity_Stakeholder__c os : stakeholders) {
            if (os.Contact__r.Stakeholder_Score__c != null) {
                totalStrength += os.Contact__r.Stakeholder_Score__c;
                count++;
            }
        }

        if (count == 0) return 50; // Default if no data

        Decimal avgStrength = totalStrength / count;
        // Convert 1-5 scale to 0-100
        return ((avgStrength - 1) / 4) * 100;
    }

    private static Decimal calculateEngagementScore(List<Opportunity_Stakeholder__c> stakeholders) {
        if (stakeholders.isEmpty()) return 0;

        Integer engagedCount = 0; // Last 14 days
        Integer recentCount = 0;  // 15-30 days
        Integer coldCount = 0;    // 30+ days or never

        Date today = Date.today();

        for (Opportunity_Stakeholder__c os : stakeholders) {
            Date lastActivity = os.Contact__r.LastActivityDate;

            if (lastActivity == null) {
                coldCount++;
            } else {
                Integer daysSince = today.daysBetween(lastActivity);
                if (daysSince <= 14) {
                    engagedCount++;
                } else if (daysSince <= 30) {
                    recentCount++;
                } else {
                    coldCount++;
                }
            }
        }

        // Weighted scoring: engaged = full points, recent = partial, cold = minimal
        Decimal score = (engagedCount * 100 + recentCount * 50 + coldCount * 10) / stakeholders.size();
        return score;
    }

    private static Decimal calculateBlockerScore(List<Opportunity_Stakeholder__c> stakeholders) {
        if (stakeholders.isEmpty()) return 0; // No stakeholders = no score

        Integer blockerCount = 0;

        for (Opportunity_Stakeholder__c os : stakeholders) {
            if (os.Role__c != null && os.Role__c.contains('Blocker')) {
                blockerCount++;
            }
        }

        if (blockerCount == 0) return 100; // No blockers = full points
        if (blockerCount == 1) return 50;  // One blocker = half points
        return 0; // Multiple blockers = no points
    }

    private static String getGrade(Decimal score) {
        if (score >= 80) return 'A';
        if (score >= 60) return 'B';
        if (score >= 40) return 'C';
        return 'D';
    }

    private static String getStatus(Decimal score) {
        if (score >= 80) return 'Strong';
        if (score >= 60) return 'Moderate';
        return 'At Risk';
    }

    // Wrapper class
    public class ScoreBreakdown {
        @AuraEnabled public Decimal totalScore;
        @AuraEnabled public String grade;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal countScore;
        @AuraEnabled public Decimal rolesScore;
        @AuraEnabled public Decimal strengthScore;
        @AuraEnabled public Decimal engagementScore;
        @AuraEnabled public Decimal blockerScore;

        public ScoreBreakdown() {
            this.totalScore = 0;
            this.countScore = 0;
            this.rolesScore = 0;
            this.strengthScore = 0;
            this.engagementScore = 0;
            this.blockerScore = 0;
        }
    }
}