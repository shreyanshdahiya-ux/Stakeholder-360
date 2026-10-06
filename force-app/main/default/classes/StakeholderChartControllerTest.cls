/**
 * @description Test class for StakeholderChartController
 */
@isTest
private class StakeholderChartControllerTest {

    @TestSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 3; i++) {
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
        insert roles;
    }

    @isTest
    static void testGetOpportunityStakeholders() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<StakeholderChartController.StakeholderNode> result =
            StakeholderChartController.getOpportunityStakeholders(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.size());
    }

    @isTest
    static void testGetAccountContacts() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        StakeholderChartController.AccountChartData result =
            StakeholderChartController.getAccountContacts(acc.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.accountInfo);
        System.assertEquals(3, result.nodes.size());
    }

    @isTest
    static void testUpdateContactRelationship() {
        List<Contact> contacts = [SELECT Id FROM Contact ORDER BY LastName LIMIT 2];

        Test.startTest();
        StakeholderChartController.updateContactRelationship(
            contacts[0].Id,
            contacts[1].Id
        );
        Test.stopTest();

        // Verify relationship exists or was updated
        Contact updatedContact = [SELECT Id, ReportsToId FROM Contact WHERE Id = :contacts[0].Id];
        System.assertEquals(contacts[1].Id, updatedContact.ReportsToId, 'ReportsTo relationship should be updated');
    }

    @isTest
    static void testAddContactToOpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // contacts[0] and contacts[1] already have OCRs from @TestSetup.
        // Use a contact that is NOT yet linked to this opportunity to avoid the
        // "already associated" duplicate-check in addContactToOpportunity.
        Contact contact = [
            SELECT Id FROM Contact
            WHERE Id NOT IN (SELECT ContactId FROM OpportunityContactRole WHERE OpportunityId = :opp.Id)
            LIMIT 1
        ];

        Test.startTest();
        StakeholderChartController.addContactToOpportunity(
            opp.Id,
            contact.Id,
            'Influencer',
            false
        );
        Test.stopTest();

        List<OpportunityContactRole> roles = [
            SELECT Id
            FROM OpportunityContactRole
            WHERE OpportunityId = :opp.Id AND ContactId = :contact.Id
        ];
        System.assert(roles.size() > 0, 'Contact should be added to opportunity');
    }

    @isTest
    static void testRemoveContactFromOpportunity() {
        OpportunityContactRole role = [SELECT Id FROM OpportunityContactRole LIMIT 1];

        Test.startTest();
        StakeholderChartController.removeContactFromOpportunity(role.Id);
        Test.stopTest();

        List<OpportunityContactRole> roles = [SELECT Id FROM OpportunityContactRole WHERE Id = :role.Id];
        System.assertEquals(0, roles.size(), 'Role should be removed');
    }

    @isTest
    static void testCalculateScore() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        StakeholderChartController.StakeholderScore result =
            StakeholderChartController.calculateScore(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.overallScore >= 0 && result.overallScore <= 100);
        System.assertEquals(true, result.hasChampion);
    }

    @isTest
    static void testChartDataStructure() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        StakeholderChartController.AccountChartData result =
            StakeholderChartController.getAccountContacts(acc.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.accountInfo);
    }
}