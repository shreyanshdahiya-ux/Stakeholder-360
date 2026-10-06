import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOpportunityAlerts from '@salesforce/apex/StakeholderAlertController.getOpportunityAlerts';

export default class StakeholderAlerts extends NavigationMixin(LightningElement) {
    @api recordId;

    alerts = [];
    isLoading = true;
    error;

    @wire(getOpportunityAlerts, { opportunityId: '$recordId' })
    wiredAlerts({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.alerts = data.map((alert, index) => ({
                ...alert,
                id: index,
                iconName: this.getIconName(alert.severity),
                variantClass: this.getVariantClass(alert.severity)
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.alerts = [];
            this.showError('Error loading alerts', error);
        }
    }

    get hasAlerts() {
        return this.alerts && this.alerts.length > 0;
    }

    get errorAlerts() {
        return this.alerts.filter(a => a.severity === 'error');
    }

    get warningAlerts() {
        return this.alerts.filter(a => a.severity === 'warning');
    }

    get successAlerts() {
        return this.alerts.filter(a => a.severity === 'success');
    }

    get alertStats() {
        return {
            errors: this.errorAlerts.length,
            warnings: this.warningAlerts.length,
            success: this.successAlerts.length
        };
    }

    getIconName(severity) {
        switch(severity) {
            case 'error': return 'utility:error';
            case 'warning': return 'utility:warning';
            case 'success': return 'utility:success';
            default: return 'utility:info';
        }
    }

    getVariantClass(severity) {
        switch(severity) {
            case 'error': return 'alert-error';
            case 'warning': return 'alert-warning';
            case 'success': return 'alert-success';
            default: return 'alert-info';
        }
    }

    handleAlertClick(event) {
        const contactId = event.currentTarget.dataset.contactId;
        if (contactId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: contactId,
                    objectApiName: 'Contact',
                    actionName: 'view'
                }
            });
        }
    }

    showError(title, error) {
        const message = error?.body?.message || error?.message || 'Unknown error';
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant: 'error'
        }));
    }
}