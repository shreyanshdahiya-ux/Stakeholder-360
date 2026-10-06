/**
 * @description Test class for StakeholderContactController
 */
@isTest
private class StakeholderContactControllerTest {

    @TestSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact contact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            AccountId = acc.Id,
            Email = 'test@test.com'
        );
        insert contact;

        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 100000
        );
        insert opp;

        OpportunityContactRole role = new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = contact.Id,
            Role = 'Champion',
            IsPrimary = true
        );
        insert role;
    }

    @isTest
    static void testGetContactProfile() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        StakeholderContactController.ContactProfile result =
            StakeholderContactController.getContactProfile(contact.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.id);
        System.assert(result.engagementScore >= 0 && result.engagementScore <= 100);
        System.assertEquals(1, result.totalOpportunities);
    }

    @isTest
    static void testGetContactOpportunities() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        StakeholderContactController.ContactProfile result =
            StakeholderContactController.getContactProfile(contact.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.opportunities);
        System.assertEquals(1, result.opportunities.size());
    }

    @isTest
    static void testContactActivities() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        StakeholderContactController.ContactProfile result =
            StakeholderContactController.getContactProfile(contact.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.recentActivities);
    }
}