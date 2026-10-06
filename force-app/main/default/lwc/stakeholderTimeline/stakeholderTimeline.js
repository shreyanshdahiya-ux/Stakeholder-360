import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getStakeholderTimeline from '@salesforce/apex/Stakeholder360Controller.getStakeholderTimeline';

export default class StakeholderTimeline extends LightningElement {
    @api recordId;

    events = [];
    isLoading = true;
    error;

    @wire(getStakeholderTimeline, { accountId: '$recordId' })
    wiredTimeline({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.events = data.map((e, idx) => ({
                ...e,
                key: 'event-' + idx,
                formattedDate: this.formatDate(e.eventDate),
                categoryClass: this.getCategoryClass(e.category),
                categoryIcon: this.getCategoryIcon(e.category)
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error?.body?.message || error?.message || 'Failed to load timeline';
            this.events = [];
            this.showError('Error loading timeline', error);
        }
    }

    get hasError() {
        return !!this.error;
    }

    get hasEvents() {
        return this.events.length > 0;
    }

    get eventCount() {
        return this.events.length;
    }

    formatDate(dateString) {
        if (!dateString) return '';
        const date = new Date(dateString);
        const options = { month: 'short', day: 'numeric', year: 'numeric' };
        return date.toLocaleDateString('en-US', options);
    }

    getCategoryClass(category) {
        const classes = {
            'stakeholder': 'event-dot stakeholder-dot',
            'relationship': 'event-dot relationship-dot',
            'sentiment': 'event-dot sentiment-dot',
            'role': 'event-dot role-dot'
        };
        return classes[category] || 'event-dot';
    }

    getCategoryIcon(category) {
        const icons = {
            'stakeholder': '👤',
            'relationship': '🔗',
            'sentiment': '💬',
            'role': '🎭'
        };
        return icons[category] || '📌';
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