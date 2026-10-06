/**
 * @description Test class for StakeholderAlertController
 * Tests alert generation logic for opportunities and accounts
 */
@isTest
private class StakeholderAlertControllerTest {

    @TestSetup
    static void setupTestData() {
        Account testAccount = new Account(Name = 'Test Account', Rating = 'Hot');
        insert testAccount;

        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 3; i++) {
            contacts.add(new Contact(
                FirstName = 'Test' + i,
                LastName = 'Contact' + i,
                AccountId = testAccount.Id,
                Email = 'test' + i + '@test.com'
            ));
        }
        insert contacts;

        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 50000
        );
        insert testOpp;

        // Add some roles
        List<OpportunityContactRole> roles = new List<OpportunityContactRole>();
        roles.add(new OpportunityContactRole(
            OpportunityId = testOpp.Id,
            ContactId = contacts[0].Id,
            Role = 'Influencer'
        ));
        insert roles;
    }

    @isTest
    static void testGetOpportunityAlerts_MissingChampion() {
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<StakeholderAlertController.StakeholderAlert> result =
            StakeholderAlertController.getOpportunityAlerts(testOpp.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.size() > 0, 'Should have alerts');

        Boolean hasMissingChampion = false;
        for (StakeholderAlertController.StakeholderAlert alert : result) {
            if (alert.title.contains('Champion')) {
                hasMissingChampion = true;
                System.assertEquals('error', alert.severity, 'Missing Champion should be error severity');
            }
        }
        System.assertEquals(true, hasMissingChampion, 'Should alert about missing Champion');
    }

    @isTest
    static void testGetOpportunityAlerts_InactiveStakeholders() {
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact ORDER BY LastName];

        // Add inactive contact as opportunity contact role
        OpportunityContactRole inactiveRole = new OpportunityContactRole(
            OpportunityId = testOpp.Id,
            ContactId = contacts[2].Id,
            Role = 'Decision Maker'
        );
        insert inactiveRole;

        Test.startTest();
        List<StakeholderAlertController.StakeholderAlert> result =
            StakeholderAlertController.getOpportunityAlerts(testOpp.Id);
        Test.stopTest();

        Boolean hasInactiveAlert = false;
        for (StakeholderAlertController.StakeholderAlert alert : result) {
            if (alert.title.contains('Inactive')) {
                hasInactiveAlert = true;
                System.assertEquals('warning', alert.severity, 'Inactive stakeholder should be warning');
            }
        }
        System.assertEquals(true, hasInactiveAlert, 'Should detect inactive stakeholder');
    }

    @isTest
    static void testGetOpportunityAlerts_HealthyOpportunity() {
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        // Get contacts not already on this opportunity's OCRs
        List<Contact> contacts = [
            SELECT Id FROM Contact
            WHERE AccountId = :testAccount.Id
            AND Id NOT IN (SELECT ContactId FROM OpportunityContactRole WHERE OpportunityId = :testOpp.Id)
            ORDER BY LastName
        ];

        // Create an extra contact for the Economic Buyer role (need Champion + DM + EB for no alerts)
        Contact extraContact = new Contact(
            FirstName = 'Extra', LastName = 'ZContact',
            AccountId = testAccount.Id, Email = 'extra_healthy@test.com'
        );
        insert extraContact;
        contacts.add(extraContact);

        // Insert Tasks so LastActivityDate is populated (avoiding inactive-stakeholder alerts)
        List<Task> tasks = new List<Task>();
        // Also cover the existing Influencer contact from @TestSetup
        List<Contact> allContacts = [SELECT Id FROM Contact WHERE AccountId = :testAccount.Id];
        for (Contact c : allContacts) {
            tasks.add(new Task(WhoId = c.Id, Subject = 'Call', Status = 'Completed', ActivityDate = Date.today()));
        }
        tasks.add(new Task(WhoId = extraContact.Id, Subject = 'Call', Status = 'Completed', ActivityDate = Date.today()));
        insert tasks;

        // Add all three key roles required for a clean bill of health
        List<OpportunityContactRole> roles = new List<OpportunityContactRole>();
        roles.add(new OpportunityContactRole(OpportunityId = testOpp.Id, ContactId = contacts[0].Id, Role = 'Champion'));
        roles.add(new OpportunityContactRole(OpportunityId = testOpp.Id, ContactId = contacts[1].Id, Role = 'Decision Maker'));
        roles.add(new OpportunityContactRole(OpportunityId = testOpp.Id, ContactId = extraContact.Id,  Role = 'Economic Buyer'));
        insert roles;

        Test.startTest();
        List<StakeholderAlertController.StakeholderAlert> result =
            StakeholderAlertController.getOpportunityAlerts(testOpp.Id);
        Test.stopTest();

        Boolean hasSuccess = false;
        for (StakeholderAlertController.StakeholderAlert alert : result) {
            if (alert.severity == 'success') {
                hasSuccess = true;
            }
        }
        System.assertEquals(true, hasSuccess, 'Healthy opportunity should show success');
    }

    @isTest
    static void testGetAccountAlerts_NoContacts() {
        // Create account with no contacts
        Account emptyAccount = new Account(Name = 'Empty Account');
        insert emptyAccount;

        Test.startTest();
        List<StakeholderAlertController.StakeholderAlert> result =
            StakeholderAlertController.getAccountAlerts(emptyAccount.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.size() > 0, 'Should have alerts');

        Boolean hasNoContactsAlert = false;
        for (StakeholderAlertController.StakeholderAlert alert : result) {
            if (alert.title.contains('No Contacts')) {
                hasNoContactsAlert = true;
            }
        }
        System.assertEquals(true, hasNoContactsAlert, 'Should alert about no contacts');
    }

    @isTest
    static void testGetAccountAlerts_InactiveContacts() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<StakeholderAlertController.StakeholderAlert> result =
            StakeholderAlertController.getAccountAlerts(testAccount.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');

        // Should detect inactive contact (65 days old)
        Boolean hasInactiveContacts = false;
        for (StakeholderAlertController.StakeholderAlert alert : result) {
            if (alert.title.contains('Inactive')) {
                hasInactiveContacts = true;
            }
        }
        System.assertEquals(true, hasInactiveContacts, 'Should detect inactive contacts');
    }

    @isTest
    static void testGetAccountAlerts_HealthyAccount() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :testAccount.Id];

        // Create tasks to simulate recent activity
        List<Task> tasks = new List<Task>();
        for (Contact c : contacts) {
            tasks.add(new Task(
                WhoId = c.Id,
                Subject = 'Test Task',
                Status = 'Completed',
                ActivityDate = Date.today()
            ));
        }
        insert tasks;

        Test.startTest();
        List<StakeholderAlertController.StakeholderAlert> result =
            StakeholderAlertController.getAccountAlerts(testAccount.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @isTest
    static void testAlertSeverityLevels() {
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<StakeholderAlertController.StakeholderAlert> result =
            StakeholderAlertController.getOpportunityAlerts(testOpp.Id);
        Test.stopTest();

        // Verify severity levels are valid
        for (StakeholderAlertController.StakeholderAlert alert : result) {
            System.assert(
                alert.severity == 'error' || alert.severity == 'warning' || alert.severity == 'success',
                'Severity should be error, warning, or success'
            );
            System.assertNotEquals(null, alert.title, 'Alert title should not be null');
            System.assertNotEquals(null, alert.message, 'Alert message should not be null');
            System.assertNotEquals(null, alert.recommendation, 'Alert recommendation should not be null');
        }
    }
}