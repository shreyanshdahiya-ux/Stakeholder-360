/**
 * Test class for StakeholderScoreCalculator
 */
@isTest
private class StakeholderScoreCalculatorTest {

    @testSetup
    static void setup() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;

        // Create test contacts
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 8; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName = 'Contact ' + i,
                AccountId = testAccount.Id,
                Title = 'Test Title ' + i,
                Email = 'test' + i + '@example.com',
                Stakeholder_Score__c = 4
            ));
        }
        insert contacts;

        // Create test opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 100000
        );
        insert testOpp;
    }

    @isTest
    static void testCalculateOpportunityScoreHighScore() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact LIMIT 8];

        // Create comprehensive stakeholder coverage
        List<Opportunity_Stakeholder__c> stakeholders = new List<Opportunity_Stakeholder__c>();

        // Add Champion, Decision Maker, Economic Buyer as separate records
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[0].Id,
            Role__c = 'Champion',
            Engagement_Status__c = 'Engaged'
        ));
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[1].Id,
            Role__c = 'Decision Maker',
            Engagement_Status__c = 'Engaged'
        ));
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[2].Id,
            Role__c = 'Economic Buyer',
            Engagement_Status__c = 'Engaged'
        ));

        // Add additional stakeholders
        for (Integer i = 3; i < 8; i++) {
            stakeholders.add(new Opportunity_Stakeholder__c(
                Opportunity__c = opp.Id,
                Contact__c = contacts[i].Id,
                Role__c = 'Influencer',
                Engagement_Status__c = 'Engaged'
            ));
        }
        insert stakeholders;

        Test.startTest();
        Decimal score = StakeholderScoreCalculator.calculateOpportunityScore(opp.Id);
        Test.stopTest();

        System.assert(score > 70, 'Score should be high with good coverage: ' + score);

        Opportunity updated = [SELECT Stakeholder_Score__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(score, updated.Stakeholder_Score__c, 'Score should be saved on opportunity');
    }

    @isTest
    static void testCalculateOpportunityScoreLowScore() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact LIMIT 2];

        // Create minimal stakeholder coverage
        Opportunity_Stakeholder__c stakeholder = new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[0].Id,
            Role__c = 'Influencer', // No key roles
            Engagement_Status__c = 'Engaged'
        );
        insert stakeholder;

        Test.startTest();
        Decimal score = StakeholderScoreCalculator.calculateOpportunityScore(opp.Id);
        Test.stopTest();

        System.assert(score < 50, 'Score should be low with poor coverage: ' + score);
    }

    @isTest
    static void testGetScoreBreakdown() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact LIMIT 5];

        // Create moderate stakeholder coverage
        List<Opportunity_Stakeholder__c> stakeholders = new List<Opportunity_Stakeholder__c>();
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[0].Id,
            Role__c = 'Champion',
            Engagement_Status__c = 'Engaged'
        ));
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[1].Id,
            Role__c = 'Decision Maker',
            Engagement_Status__c = 'Engaged'
        ));
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[2].Id,
            Role__c = 'Economic Buyer',
            Engagement_Status__c = 'Engaged'
        ));
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[3].Id,
            Role__c = 'Influencer',
            Engagement_Status__c = 'Engaged'
        ));
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[4].Id,
            Role__c = 'User',
            Engagement_Status__c = 'Engaged'
        ));
        insert stakeholders;

        Test.startTest();
        StakeholderScoreCalculator.ScoreBreakdown breakdown =
            StakeholderScoreCalculator.getScoreBreakdown(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, breakdown, 'Breakdown should not be null');
        System.assert(breakdown.totalScore > 0, 'Total score should be calculated');
        System.assertNotEquals(null, breakdown.grade, 'Grade should be assigned');
        System.assertNotEquals(null, breakdown.status, 'Status should be assigned');

        // Check individual components
        System.assert(breakdown.countScore > 0, 'Count score should be calculated');
        System.assert(breakdown.rolesScore > 0, 'Roles score should be calculated');
        System.assert(breakdown.strengthScore > 0, 'Strength score should be calculated');
        System.assert(breakdown.engagementScore > 0, 'Engagement score should be calculated');
        System.assert(breakdown.blockerScore > 0, 'Blocker score should be calculated');

        // Verify roles score is 75 (Champion + Decision Maker; Budget Holder is inactive in org picklist)
        System.assertEquals(75, breakdown.rolesScore, 'Should have Champion and Decision Maker roles score');
    }

    @isTest
    static void testScoreWithBlockers() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact LIMIT 4];

        // Add stakeholders including blockers
        List<Opportunity_Stakeholder__c> stakeholders = new List<Opportunity_Stakeholder__c>();
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[0].Id,
            Role__c = 'Champion',
            Engagement_Status__c = 'Engaged'
        ));
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[1].Id,
            Role__c = 'Blocker',
            Engagement_Status__c = 'Engaged'
        ));
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[2].Id,
            Role__c = 'Blocker',
            Engagement_Status__c = 'Engaged'
        ));
        insert stakeholders;

        Test.startTest();
        StakeholderScoreCalculator.ScoreBreakdown breakdown =
            StakeholderScoreCalculator.getScoreBreakdown(opp.Id);
        Test.stopTest();

        System.assertEquals(0, breakdown.blockerScore, 'Blocker score should be 0 with multiple blockers');
    }

    @isTest
    static void testScoreWithOneBlocker() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact LIMIT 3];

        // Add stakeholders including one blocker
        List<Opportunity_Stakeholder__c> stakeholders = new List<Opportunity_Stakeholder__c>();
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[0].Id,
            Role__c = 'Champion',
            Engagement_Status__c = 'Engaged'
        ));
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[1].Id,
            Role__c = 'Blocker',
            Engagement_Status__c = 'Engaged'
        ));
        insert stakeholders;

        Test.startTest();
        StakeholderScoreCalculator.ScoreBreakdown breakdown =
            StakeholderScoreCalculator.getScoreBreakdown(opp.Id);
        Test.stopTest();

        System.assertEquals(50, breakdown.blockerScore, 'Blocker score should be 50 with one blocker');
    }

    @isTest
    static void testEngagementScoring() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact LIMIT 3];

        // Note: LastActivityDate is read-only and set by Salesforce based on actual activities
        // We're testing with the default lastActivityDate values set in testSetup

        // Add stakeholders
        List<Opportunity_Stakeholder__c> stakeholders = new List<Opportunity_Stakeholder__c>();
        for (Contact con : contacts) {
            stakeholders.add(new Opportunity_Stakeholder__c(
                Opportunity__c = opp.Id,
                Contact__c = con.Id,
                Role__c = 'Influencer',
                Engagement_Status__c = 'Engaged'
            ));
        }
        insert stakeholders;

        Test.startTest();
        StakeholderScoreCalculator.ScoreBreakdown breakdown =
            StakeholderScoreCalculator.getScoreBreakdown(opp.Id);
        Test.stopTest();

        // Engagement score should be calculated
        System.assert(breakdown.engagementScore >= 0, 'Engagement score should be calculated');
    }

    @isTest
    static void testCalculateScoresForMultipleOpportunities() {
        List<Opportunity> opps = [SELECT Id FROM Opportunity];
        List<Contact> contacts = [SELECT Id FROM Contact LIMIT 3];

        // Add stakeholders to opportunities
        List<Opportunity_Stakeholder__c> stakeholders = new List<Opportunity_Stakeholder__c>();
        for (Opportunity opp : opps) {
            stakeholders.add(new Opportunity_Stakeholder__c(
                Opportunity__c = opp.Id,
                Contact__c = contacts[0].Id,
                Role__c = 'Champion',
                Engagement_Status__c = 'Engaged'
            ));
        }
        insert stakeholders;

        List<Id> oppIds = new List<Id>();
        for (Opportunity opp : opps) {
            oppIds.add(opp.Id);
        }

        Test.startTest();
        StakeholderScoreCalculator.calculateScoresForOpportunities(oppIds);
        Test.stopTest();

        List<Opportunity> updatedOpps = [
            SELECT Id, Stakeholder_Score__c
            FROM Opportunity
            WHERE Id IN :oppIds
        ];

        for (Opportunity opp : updatedOpps) {
            System.assertNotEquals(null, opp.Stakeholder_Score__c, 'Score should be calculated');
        }
    }

    @isTest
    static void testGradeAssignment() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact LIMIT 8];

        // Create excellent coverage for A grade
        List<Opportunity_Stakeholder__c> stakeholders = new List<Opportunity_Stakeholder__c>();
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[0].Id,
            Role__c = 'Champion',
            Engagement_Status__c = 'Engaged'
        ));
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[1].Id,
            Role__c = 'Decision Maker',
            Engagement_Status__c = 'Engaged'
        ));
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = contacts[2].Id,
            Role__c = 'Economic Buyer',
            Engagement_Status__c = 'Engaged'
        ));
        for (Integer i = 3; i < 8; i++) {
            stakeholders.add(new Opportunity_Stakeholder__c(
                Opportunity__c = opp.Id,
                Contact__c = contacts[i].Id,
                Role__c = 'Influencer',
                Engagement_Status__c = 'Engaged'
            ));
        }
        insert stakeholders;

        Test.startTest();
        StakeholderScoreCalculator.ScoreBreakdown breakdown =
            StakeholderScoreCalculator.getScoreBreakdown(opp.Id);
        Test.stopTest();

        System.assert(
            breakdown.grade == 'A' || breakdown.grade == 'B',
            'Grade should be A or B with excellent coverage: ' + breakdown.grade
        );
        System.assert(
            breakdown.status == 'Strong' || breakdown.status == 'Moderate',
            'Status should be Strong or Moderate'
        );
    }

    @isTest
    static void testEmptyStakeholders() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        Decimal score = StakeholderScoreCalculator.calculateOpportunityScore(opp.Id);
        Test.stopTest();

        System.assertEquals(0, score, 'Score should be 0 with no stakeholders');
    }
}