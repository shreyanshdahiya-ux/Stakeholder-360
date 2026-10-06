/**
 * @description Test class for StakeholderAccountController
 */
@isTest
private class StakeholderAccountControllerTest {

    @TestSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Test Account', Rating = 'Hot');
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
            Name = 'Test Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
    }

    @isTest
    static void testGetAccountSummary() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        StakeholderAccountController.AccountSummary result =
            StakeholderAccountController.getAccountSummary(acc.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(5, result.totalContacts);
        System.assert(result.healthScore >= 0 && result.healthScore <= 100);
    }

    @isTest
    static void testGetKeyContacts() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<StakeholderAccountController.ContactInfo> result =
            StakeholderAccountController.getKeyContacts(acc.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(5, result.size());
    }

    @isTest
    static void testAccountHealthScore() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        StakeholderAccountController.AccountSummary result =
            StakeholderAccountController.getAccountSummary(acc.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.totalContacts >= 0);
        System.assert(result.activeContacts >= 0);
        System.assert(result.healthScore >= 0 && result.healthScore <= 100);
    }
}