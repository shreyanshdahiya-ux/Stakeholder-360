import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getContactPhoto from '@salesforce/apex/ContactPhotoController.getContactPhoto';
import uploadProfilePicture from '@salesforce/apex/ContactPhotoController.uploadProfilePicture';
import deleteContactPhoto from '@salesforce/apex/ContactPhotoController.deleteContactPhoto';

export default class ContactPhotoUpload extends LightningElement {
    @api recordId;

    photoUrl = null;
    photoDocumentId = null;
    selectedFile = null;
    fileName = null;
    isLoading = false;
    isRefreshing = false;
    _retryCount = 0;

    connectedCallback() {
        this.loadPhoto();
    }

    handleImageError() {
        if (this._retryCount < 5) {
            this._retryCount++;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this.loadPhoto(), 2000);
        }
    }

    loadPhoto() {
        return getContactPhoto({ contactId: this.recordId })
            .then(data => {
                if (data && data.photoUrl) {
                    const sep = data.photoUrl.includes('?') ? '&' : '?';
                    this.photoUrl = data.photoUrl + sep + 't=' + Date.now();
                    this.photoDocumentId = data.documentId;
                } else {
                    this.photoUrl = null;
                    this.photoDocumentId = null;
                }
            })
            .catch(() => {
                this.photoUrl = null;
                this.photoDocumentId = null;
            });
    }

    get hasPhoto() {
        return this.photoUrl != null && this.photoUrl !== '';
    }

    get isUploadDisabled() {
        return !this.selectedFile || this.isLoading;
    }

    handleFileChange(event) {
        const files = event.detail.files;
        if (!files || files.length === 0) return;

        const file = files[0];

        const maxSize = 5 * 1024 * 1024;
        if (file.size > maxSize) {
            this.showToast('Error', 'File size must be less than 5MB', 'error');
            this.selectedFile = null;
            this.fileName = null;
            return;
        }

        const allowedTypes = ['image/png', 'image/jpeg', 'image/jpg', 'image/gif'];
        if (!allowedTypes.includes(file.type)) {
            this.showToast('Error', 'Only PNG, JPG, JPEG, and GIF files are allowed', 'error');
            this.selectedFile = null;
            this.fileName = null;
            return;
        }

        this.fileName = file.name;

        const reader = new FileReader();
        reader.onload = () => {
            this.selectedFile = reader.result.split(',')[1];
        };
        reader.readAsDataURL(file);
    }

    handleUpload() {
        if (!this.selectedFile) {
            this.showToast('Error', 'Please select a file', 'error');
            return;
        }

        this.isLoading = true;
        this._retryCount = 0;

        uploadProfilePicture({
            contactId: this.recordId,
            fileName: this.fileName,
            base64Data: this.selectedFile
        })
        .then(() => {
            this.showToast('Success', 'Profile picture uploaded successfully!', 'success');
            this.selectedFile = null;
            this.fileName = null;

            const fileInput = this.template.querySelector('lightning-input[type="file"]');
            if (fileInput) {
                fileInput.value = '';
            }

            return this.loadPhoto();
        })
        .catch(error => {
            const errorMsg = error?.body?.message || 'Failed to upload profile picture';
            this.showToast('Error', errorMsg, 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    handleRefresh() {
        this.isRefreshing = true;
        this.loadPhoto().finally(() => {
            this.isRefreshing = false;
        });
    }

    async handleRemovePhoto() {
        if (!this.photoDocumentId) {
            this.showToast('Error', 'No photo to remove', 'error');
            return;
        }

        try {
            await deleteContactPhoto({
                contactId: this.recordId,
                documentId: this.photoDocumentId
            });
            this.showToast('Success', 'Photo removed successfully', 'success');
            this.photoUrl = null;
            this.photoDocumentId = null;
        } catch (error) {
            const errorMsg = error?.body?.message || 'Failed to remove photo';
            this.showToast('Error', errorMsg, 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}