public with sharing class StakeholderOpportunityController {

    @AuraEnabled(cacheable=true)
    public static OpportunityInsights getOpportunityInsights(Id opportunityId) {
        // Input validation
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity ID is required');
        }

        OpportunityInsights insights = new OpportunityInsights();

        try {
            // Get opportunity details
            Opportunity opp = [
                SELECT Id, Name, StageName, Amount, CloseDate, AccountId,
                       Account.Name, Probability, Description
                FROM Opportunity
                WHERE Id = :opportunityId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            insights.opportunityName = opp.Name;
            insights.stageName = opp.StageName;
            insights.amount = opp.Amount;
            insights.closeDate = opp.CloseDate;
            insights.accountName = opp.Account.Name;
            insights.probability = opp.Probability != null ? opp.Probability.intValue() : 0;

            // Get stakeholder roles
            List<OpportunityContactRole> roles = [
                SELECT Id, ContactId, Contact.Name, Contact.Title, Contact.Email,
                       Contact.LastActivityDate, Contact.Photo_URL__c,
                       Contact.Relationship_Strength__c, Role, IsPrimary
                FROM OpportunityContactRole
                WHERE OpportunityId = :opportunityId
                WITH SECURITY_ENFORCED
                ORDER BY IsPrimary DESC, Role
            ];

            insights.totalStakeholders = roles.size();
            insights.championCount = 0;
            insights.decisionMakerCount = 0;
            insights.economicBuyerCount = 0;

            Map<String, Integer> roleCounts = new Map<String, Integer>();
            Date thirtyDaysAgo = Date.today().addDays(-30);
            Integer inactiveCount = 0;
            Decimal totalStrength = 0;
            Integer strengthCount = 0;

            insights.stakeholders = new List<StakeholderDetail>();

            for (OpportunityContactRole ocr : roles) {
                if (ocr.Role == 'Champion') insights.championCount++;
                if (ocr.Role == 'Decision Maker') insights.decisionMakerCount++;
                if (ocr.Role == 'Economic Buyer') insights.economicBuyerCount++;

                Integer count = roleCounts.containsKey(ocr.Role) ? roleCounts.get(ocr.Role) : 0;
                roleCounts.put(ocr.Role, count + 1);

                if (ocr.Contact.LastActivityDate == null ||
                    ocr.Contact.LastActivityDate < thirtyDaysAgo) {
                    inactiveCount++;
                }

                if (ocr.Contact.Relationship_Strength__c != null) {
                    totalStrength += ocr.Contact.Relationship_Strength__c;
                    strengthCount++;
                }

                StakeholderDetail detail = new StakeholderDetail();
                detail.id = ocr.ContactId;
                detail.name = ocr.Contact.Name;
                detail.title = ocr.Contact.Title;
                detail.email = ocr.Contact.Email;
                detail.role = ocr.Role;
                detail.isPrimary = ocr.IsPrimary;
                detail.relationshipStrength = ocr.Contact.Relationship_Strength__c != null
                    ? ocr.Contact.Relationship_Strength__c.intValue()
                    : 0;
                detail.lastActivityDate = ocr.Contact.LastActivityDate;
                detail.photoUrl = ocr.Contact.Photo_URL__c;
                detail.isActive = ocr.Contact.LastActivityDate != null &&
                    ocr.Contact.LastActivityDate >= thirtyDaysAgo;

                insights.stakeholders.add(detail);
            }

            insights.averageRelationshipStrength = strengthCount > 0
                ? (totalStrength / strengthCount).setScale(1)
                : 0;
            insights.inactiveStakeholders = inactiveCount;

            // Role distribution
            insights.roleDistribution = new List<RoleDistribution>();
            for (String role : roleCounts.keySet()) {
                insights.roleDistribution.add(new RoleDistribution(role, roleCounts.get(role)));
            }

            // Calculate health metrics
            insights.coverageHealth = calculateCoverageHealth(insights);
            insights.relationshipHealth = calculateRelationshipHealth(insights);
            insights.engagementHealth = calculateEngagementHealth(insights);

            // Generate insights/recommendations
            insights.insights = generateInsights(insights);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading opportunity insights: ' + e.getMessage());
            throw new AuraHandledException('Unable to load opportunity insights');
        }

        return insights;
    }

    private static Integer calculateCoverageHealth(OpportunityInsights insights) {
        Integer health = 0;

        // Total stakeholders (40 points)
        if (insights.totalStakeholders >= 5) health += 40;
        else health += insights.totalStakeholders * 8;

        // Key roles (60 points)
        if (insights.championCount > 0) health += 20;
        if (insights.decisionMakerCount > 0) health += 20;
        if (insights.economicBuyerCount > 0) health += 20;

        return health;
    }

    private static Integer calculateRelationshipHealth(OpportunityInsights insights) {
        if (insights.averageRelationshipStrength == null || insights.averageRelationshipStrength == 0) return 0;
        return ((insights.averageRelationshipStrength / 5) * 100).intValue();
    }

    private static Integer calculateEngagementHealth(OpportunityInsights insights) {
        if (insights.totalStakeholders == 0) return 0;

        Integer activeCount = insights.totalStakeholders - insights.inactiveStakeholders;
        Decimal engagementRate = (Decimal.valueOf(activeCount) / insights.totalStakeholders) * 100;

        return engagementRate.intValue();
    }

    private static List<String> generateInsights(OpportunityInsights insights) {
        List<String> insightsList = new List<String>();

        // Coverage insights
        if (insights.championCount == 0) {
            insightsList.add('No Champion identified - find an internal advocate to champion your solution');
        }
        if (insights.decisionMakerCount == 0) {
            insightsList.add('Missing Decision Maker - connect with the final decision authority');
        }
        if (insights.totalStakeholders < 3) {
            insightsList.add('Limited stakeholder coverage increases risk - aim for at least 3-5 key contacts');
        }

        // Engagement insights
        if (insights.inactiveStakeholders > 0) {
            insightsList.add(insights.inactiveStakeholders + ' stakeholder(s) inactive for 30+ days - re-engage soon');
        }

        // Positive insights
        if (insights.championCount > 0 && insights.decisionMakerCount > 0 && insights.economicBuyerCount > 0) {
            insightsList.add('Excellent stakeholder coverage across all key roles - maintain regular engagement');
        }

        return insightsList;
    }

    public class OpportunityInsights {
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String stageName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public String accountName;
        @AuraEnabled public Integer probability;
        @AuraEnabled public Integer totalStakeholders;
        @AuraEnabled public Integer championCount;
        @AuraEnabled public Integer decisionMakerCount;
        @AuraEnabled public Integer economicBuyerCount;
        @AuraEnabled public Decimal averageRelationshipStrength;
        @AuraEnabled public Integer inactiveStakeholders;
        @AuraEnabled public Integer coverageHealth;
        @AuraEnabled public Integer relationshipHealth;
        @AuraEnabled public Integer engagementHealth;
        @AuraEnabled public List<StakeholderDetail> stakeholders;
        @AuraEnabled public List<RoleDistribution> roleDistribution;
        @AuraEnabled public List<String> insights;
    }

    public class StakeholderDetail {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String email;
        @AuraEnabled public String role;
        @AuraEnabled public Boolean isPrimary;
        @AuraEnabled public Integer relationshipStrength;
        @AuraEnabled public Date lastActivityDate;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public Boolean isActive;
    }

    public class RoleDistribution {
        @AuraEnabled public String role;
        @AuraEnabled public Integer count;

        public RoleDistribution(String role, Integer count) {
            this.role = role;
            this.count = count;
        }
    }
}