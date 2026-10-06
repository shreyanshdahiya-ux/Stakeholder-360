public with sharing class ContactPhotoController {

    @AuraEnabled
    public static PhotoData getContactPhoto(Id contactId) {
        // Input validation
        if (contactId == null) {
            throw new AuraHandledException('Contact ID is required');
        }

        PhotoData photoData = new PhotoData();

        try {
            // Get photo URL from Contact field with FLS enforcement
            List<Contact> contacts = [
                SELECT Id, Photo_URL__c
                FROM Contact
                WHERE Id = :contactId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (!contacts.isEmpty() && contacts[0].Photo_URL__c != null) {
                photoData.photoUrl = contacts[0].Photo_URL__c;
            }

            // Get the latest document ID for deletion
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :contactId
                AND ContentDocument.FileType IN ('PNG', 'JPG', 'JPEG', 'GIF')
                WITH SECURITY_ENFORCED
                ORDER BY ContentDocument.CreatedDate DESC
                LIMIT 1
            ];

            if (!links.isEmpty()) {
                photoData.documentId = links[0].ContentDocumentId;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting contact photo: ' + e.getMessage());
            throw new AuraHandledException('Unable to load contact photo');
        }

        return photoData;
    }

    @AuraEnabled
    public static String uploadProfilePicture(Id contactId, String fileName, String base64Data) {
        // Input validation
        if (contactId == null) {
            throw new AuraHandledException('Contact ID is required');
        }
        if (String.isBlank(fileName)) {
            throw new AuraHandledException('File name is required');
        }
        if (String.isBlank(base64Data)) {
            throw new AuraHandledException('File data is required');
        }

        // Validate file size (base64 is ~33% larger than binary)
        Integer maxBase64Size = 7000000; // ~5MB binary
        if (base64Data.length() > maxBase64Size) {
            throw new AuraHandledException('File size exceeds 5MB limit');
        }

        // Validate fileName for path traversal
        if (fileName.contains('..') || fileName.contains('/') || fileName.contains('\\')) {
            throw new AuraHandledException('Invalid file name');
        }

        try {
            // CRUD check for ContentVersion
            if (!ContentVersion.sObjectType.getDescribe().isCreateable()) {
                throw new AuraHandledException('Insufficient privileges to upload files');
            }

            // Create ContentVersion
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = EncodingUtil.base64Decode(base64Data);
            cv.FirstPublishLocationId = contactId;
            SObjectAccessDecision sd = Security.stripInaccessible(AccessType.CREATABLE, new List<ContentVersion>{cv});
            insert sd.getRecords();
            cv = (ContentVersion) sd.getRecords()[0];

            // Get the ContentDocumentId
            cv = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :cv.Id
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // Build the photo URL
            String photoUrl = '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + cv.Id;

            // CRUD check for Contact update
            if (!Contact.sObjectType.getDescribe().isUpdateable()) {
                throw new AuraHandledException('Insufficient privileges to update contact');
            }

            // FLS check for Photo_URL__c field
            if (!Contact.Photo_URL__c.getDescribe().isUpdateable()) {
                throw new AuraHandledException('Insufficient privileges to update photo field');
            }

            // Update Contact with photo URL
            Contact contact = new Contact(Id = contactId);
            contact.Photo_URL__c = photoUrl;
            update contact;

            return photoUrl;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error uploading profile picture: ' + e.getMessage());
            throw new AuraHandledException('Unable to upload profile picture');
        }
    }

    @AuraEnabled
    public static void updateContactPhotoUrl(Id contactId, Id contentVersionId) {
        // Input validation
        if (contactId == null) {
            throw new AuraHandledException('Contact ID is required');
        }
        if (contentVersionId == null) {
            throw new AuraHandledException('Content Version ID is required');
        }

        try {
            // Get the ContentVersion with FLS enforcement
            List<ContentVersion> cvList = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :contentVersionId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (cvList.isEmpty()) {
                throw new AuraHandledException('Content version not found');
            }

            ContentVersion cv = cvList[0];

            // Build the photo URL
            String photoUrl = '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + cv.Id;

            // CRUD check for Contact update
            if (!Contact.sObjectType.getDescribe().isUpdateable()) {
                throw new AuraHandledException('Insufficient privileges to update contact');
            }

            // FLS check for Photo_URL__c field
            if (!Contact.Photo_URL__c.getDescribe().isUpdateable()) {
                throw new AuraHandledException('Insufficient privileges to update photo field');
            }

            // Update Contact with photo URL
            Contact contact = new Contact(Id = contactId);
            contact.Photo_URL__c = photoUrl;
            update contact;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error updating contact photo URL: ' + e.getMessage());
            throw new AuraHandledException('Unable to update contact photo');
        }
    }

    @AuraEnabled
    public static void deleteContactPhoto(Id contactId, Id documentId) {
        // Input validation
        if (contactId == null) {
            throw new AuraHandledException('Contact ID is required');
        }
        if (documentId == null) {
            throw new AuraHandledException('Document ID is required');
        }

        try {
            // SECURITY: Verify the document belongs to this contact
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :contactId
                AND ContentDocumentId = :documentId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (links.isEmpty()) {
                throw new AuraHandledException('Document not found for this contact');
            }

            // CRUD check before delete
            if (!ContentDocument.sObjectType.getDescribe().isDeletable()) {
                throw new AuraHandledException('Insufficient privileges to delete documents');
            }

            // Delete the ContentDocument
            delete new ContentDocument(Id = documentId);

            // CRUD check for Contact update
            if (!Contact.sObjectType.getDescribe().isUpdateable()) {
                throw new AuraHandledException('Insufficient privileges to update contact');
            }

            // FLS check for Photo_URL__c field
            if (!Contact.Photo_URL__c.getDescribe().isUpdateable()) {
                throw new AuraHandledException('Insufficient privileges to update photo field');
            }

            // Clear the photo URL from Contact
            Contact contact = new Contact(Id = contactId);
            contact.Photo_URL__c = null;
            update contact;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error deleting photo: ' + e.getMessage());
            throw new AuraHandledException('Unable to delete photo');
        }
    }

    public class PhotoData {
        @AuraEnabled public Id documentId;
        @AuraEnabled public String photoUrl;
    }
}