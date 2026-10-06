/**
 * @description Test class for ContactPhotoController
 */
@isTest
private class ContactPhotoControllerTest {

    @TestSetup
    static void setupTestData() {
        Contact contact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@test.com'
        );
        insert contact;
    }

    @isTest
    static void testGetContactPhoto_NoPhoto() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        ContactPhotoController.PhotoData result =
            ContactPhotoController.getContactPhoto(contact.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(null, result.photoUrl, 'Should have no photo URL initially');
    }

    @isTest
    static void testGetContactPhoto_WithPhoto() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        ContentVersion cv = new ContentVersion();
        cv.Title = 'profile';
        cv.PathOnClient = 'profile.png';
        cv.VersionData = Blob.valueOf('test image data');
        cv.FirstPublishLocationId = contact.Id;
        insert cv;

        contact.Photo_URL__c = '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + cv.Id;
        update contact;

        Test.startTest();
        ContactPhotoController.PhotoData result =
            ContactPhotoController.getContactPhoto(contact.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.photoUrl, 'Should have photo URL');
    }

    @isTest
    static void testGetContactPhoto_NullId() {
        Test.startTest();
        try {
            ContactPhotoController.getContactPhoto(null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testUploadProfilePicture() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        String base64Data = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

        Test.startTest();
        String photoUrl = ContactPhotoController.uploadProfilePicture(
            contact.Id,
            'test.png',
            base64Data
        );
        Test.stopTest();

        System.assertNotEquals(null, photoUrl, 'Photo URL should be returned');
        System.assert(photoUrl.contains('servlet.shepherd'), 'URL should contain servlet path');
    }

    @isTest
    static void testUploadProfilePicture_NullContactId() {
        Test.startTest();
        try {
            ContactPhotoController.uploadProfilePicture(null, 'test.png', 'abc123');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testUploadProfilePicture_BlankFileName() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        try {
            ContactPhotoController.uploadProfilePicture(contact.Id, '', 'abc123');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testUploadProfilePicture_BlankBase64() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        try {
            ContactPhotoController.uploadProfilePicture(contact.Id, 'test.png', '');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testUploadProfilePicture_PathTraversal() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        try {
            ContactPhotoController.uploadProfilePicture(contact.Id, '../evil.png', 'abc123');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateContactPhotoUrl() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        ContentVersion cv = new ContentVersion();
        cv.Title = 'profile';
        cv.PathOnClient = 'profile.png';
        cv.VersionData = Blob.valueOf('test image data');
        cv.FirstPublishLocationId = contact.Id;
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        ContactPhotoController.updateContactPhotoUrl(contact.Id, cv.Id);
        Test.stopTest();

        Contact updated = [SELECT Photo_URL__c FROM Contact WHERE Id = :contact.Id];
        System.assertNotEquals(null, updated.Photo_URL__c, 'Photo URL should be set');
        System.assert(updated.Photo_URL__c.contains('servlet.shepherd'), 'URL should contain servlet path');
    }

    @isTest
    static void testUpdateContactPhotoUrl_NullContactId() {
        Test.startTest();
        try {
            ContactPhotoController.updateContactPhotoUrl(null, null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateContactPhotoUrl_NullVersionId() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        try {
            ContactPhotoController.updateContactPhotoUrl(contact.Id, null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateContactPhotoUrl_NotFound() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        ContentVersion cv = new ContentVersion();
        cv.Title = 'temp';
        cv.PathOnClient = 'temp.png';
        cv.VersionData = Blob.valueOf('temp data');
        cv.FirstPublishLocationId = contact.Id;
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        Id cvId = cv.Id;

        // Delete document so ContentVersion no longer exists
        delete new ContentDocument(Id = cv.ContentDocumentId);

        Test.startTest();
        try {
            ContactPhotoController.updateContactPhotoUrl(contact.Id, cvId);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testDeleteContactPhoto() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        ContentVersion cv = new ContentVersion();
        cv.Title = 'test';
        cv.PathOnClient = 'test.png';
        cv.VersionData = Blob.valueOf('test data');
        cv.FirstPublishLocationId = contact.Id;
        insert cv;

        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        ContactPhotoController.deleteContactPhoto(contact.Id, cv.ContentDocumentId);
        Test.stopTest();

        List<ContentDocument> docs = [SELECT Id FROM ContentDocument WHERE Id = :cv.ContentDocumentId];
        System.assertEquals(0, docs.size(), 'Photo should be deleted');
    }

    @isTest
    static void testDeleteContactPhoto_NullContactId() {
        Test.startTest();
        try {
            ContactPhotoController.deleteContactPhoto(null, null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testDeleteContactPhoto_NullDocumentId() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        try {
            ContactPhotoController.deleteContactPhoto(contact.Id, null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testDeleteContactPhoto_DocumentNotLinked() {
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        // Create document linked to a different contact
        Contact otherContact = new Contact(FirstName = 'Other', LastName = 'Contact');
        insert otherContact;

        ContentVersion cv = new ContentVersion();
        cv.Title = 'other';
        cv.PathOnClient = 'other.png';
        cv.VersionData = Blob.valueOf('other data');
        cv.FirstPublishLocationId = otherContact.Id;
        insert cv;

        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        try {
            ContactPhotoController.deleteContactPhoto(contact.Id, cv.ContentDocumentId);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }
}