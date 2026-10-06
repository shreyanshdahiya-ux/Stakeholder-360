import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class StakeholderForm extends LightningElement {
    @api stakeholderId;
    @api accountId;

    isLoading = false;
    errorMessage = null;

    get hasError() {
        return !!this.errorMessage;
    }

    get submitButtonLabel() {
        return this.stakeholderId ? 'Save Changes' : 'Create Stakeholder';
    }

    get isNewRecord() {
        return !this.stakeholderId;
    }

    handleSubmit(event) {
        this.isLoading = true;
        this.errorMessage = null;

        const fields = event.detail.fields;

        // Auto-set account for new records
        if (this.isNewRecord && this.accountId) {
            fields.Account__c = this.accountId;
        }

        // Always prevent default and submit with modified fields
        event.preventDefault();
        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    handleSuccess(event) {
        this.isLoading = false;
        this.errorMessage = null;
        const recordId = event.detail.id;

        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message: this.isNewRecord ? 'Stakeholder created successfully' : 'Stakeholder updated successfully',
            variant: 'success'
        }));

        this.dispatchEvent(new CustomEvent('save', {
            detail: { recordId },
            bubbles: true
        }));
    }

    handleError(event) {
        this.isLoading = false;
        this.errorMessage = event.detail?.output?.errors?.[0]?.message
            || event.detail?.message
            || 'Failed to save stakeholder. Please check the form and try again.';

        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: this.errorMessage,
            variant: 'error',
            mode: 'sticky'
        }));
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel', {
            bubbles: true,
            composed: true
        }));
    }
}