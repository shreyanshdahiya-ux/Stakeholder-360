import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getNextBestActions from '@salesforce/apex/Stakeholder360Controller.getNextBestActions';

export default class StakeholderNextActions extends LightningElement {
    @api recordId;

    actions = [];
    isLoading = true;
    error;

    @wire(getNextBestActions, { accountId: '$recordId' })
    wiredActions({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.actions = data.map((a, idx) => ({
                ...a,
                key: 'action-' + idx,
                urgencyClass: this.getUrgencyClass(a.urgency),
                categoryIcon: this.getCategoryIcon(a.category),
                priorityLabel: this.getPriorityLabel(a.priority)
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.actions = [];
            this.showError('Error loading actions', error);
        }
    }

    get hasActions() {
        return this.actions && this.actions.length > 0;
    }

    get actionCount() {
        return this.actions ? this.actions.length : 0;
    }

    get highPriorityCount() {
        return this.actions ? this.actions.filter(a => a.urgency === 'High').length : 0;
    }

    getUrgencyClass(urgency) {
        if (urgency === 'High') return 'urgency-badge urgency-high';
        if (urgency === 'Medium') return 'urgency-badge urgency-medium';
        return 'urgency-badge urgency-low';
    }

    getCategoryIcon(category) {
        const icons = {
            'coverage': '📊',
            'risk': '🚨',
            'engagement': '📅',
            'sentiment': '💬',
            'competitor': '⚔️'
        };
        return icons[category] || '💡';
    }

    getPriorityLabel(priority) {
        return priority ? 'P' + priority : '';
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