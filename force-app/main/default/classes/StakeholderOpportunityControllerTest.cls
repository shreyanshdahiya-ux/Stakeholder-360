/**
 * @description Test class for StakeholderOpportunityController
 */
@isTest
private class StakeholderOpportunityControllerTest {

    @TestSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName = 'Contact' + i,
                AccountId = acc.Id,
                Email = 'test' + i + '@test.com'
            ));
        }
        insert contacts;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 100000
        );
        insert opp;

        List<OpportunityContactRole> roles = new List<OpportunityContactRole>();
        roles.add(new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = contacts[0].Id,
            Role = 'Champion',
            IsPrimary = true
        ));
        roles.add(new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = contacts[1].Id,
            Role = 'Decision Maker'
        ));
        roles.add(new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = contacts[2].Id,
            Role = 'Economic Buyer'
        ));
        insert roles;
    }

    @isTest
    static void testGetOpportunityInsights() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        StakeholderOpportunityController.OpportunityInsights result =
            StakeholderOpportunityController.getOpportunityInsights(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.coverageHealth >= 0 && result.coverageHealth <= 100);
        System.assert(result.championCount > 0, 'Should have a champion');
        System.assert(result.decisionMakerCount > 0, 'Should have a decision maker');
    }

    @isTest
    static void testStakeholderDetails() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        StakeholderOpportunityController.OpportunityInsights result =
            StakeholderOpportunityController.getOpportunityInsights(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.stakeholders);
        System.assertEquals(3, result.stakeholders.size());
    }

    @isTest
    static void testEngagementHealth() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        StakeholderOpportunityController.OpportunityInsights result =
            StakeholderOpportunityController.getOpportunityInsights(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.engagementHealth >= 0 && result.engagementHealth <= 100);
    }
}