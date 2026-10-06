import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getContactProfile from '@salesforce/apex/StakeholderContactController.getContactProfile';

export default class StakeholderContactProfile extends NavigationMixin(LightningElement) {
    @api recordId;

    profile = {};
    isLoading = true;
    showAllOpportunities = false;
    errorMessage = null;

    @wire(getContactProfile, { contactId: '$recordId' })
    wiredProfile({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.profile = data;
            this.errorMessage = null;
        } else if (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Failed to load contact profile';
            this.showError('Error loading profile', error);
        }
    }

    get hasProfile() {
        return this.profile && this.profile.name;
    }

    get engagementScoreClass() {
        if (!this.hasProfile) return 'engagement-score';
        const score = this.profile.engagementScore;
        if (score >= 80) return 'engagement-score score-high';
        if (score >= 50) return 'engagement-score score-medium';
        return 'engagement-score score-low';
    }

    get engagementLevel() {
        if (!this.hasProfile) return 'Unknown';
        const score = this.profile.engagementScore;
        if (score >= 80) return 'Highly Engaged';
        if (score >= 50) return 'Moderately Engaged';
        return 'Low Engagement';
    }

    get strengthStars() {
        if (!this.hasProfile) return [];
        const strength = this.profile.relationshipStrength;
        return Array(5).fill(0).map((_, i) => ({
            id: i,
            iconName: i < strength ? 'utility:favorite' : 'utility:favorite_off',
            cssClass: i < strength ? 'star-filled' : 'star-empty'
        }));
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get hasOpportunities() {
        return this.profile.opportunities && this.profile.opportunities.length > 0;
    }

    get displayedOpportunities() {
        if (!this.hasOpportunities) return [];
        const opps = this.showAllOpportunities
            ? this.profile.opportunities
            : this.profile.opportunities.slice(0, 5);
        return opps.map(o => ({
            ...o,
            formattedAmount: this.formatAmount(o.amount),
            formattedCloseDate: this.formatDate(o.closeDate)
        }));
    }

    get showToggleButton() {
        return this.hasOpportunities && this.profile.opportunities.length > 5;
    }

    get toggleButtonLabel() {
        return this.showAllOpportunities ? 'Show Less' : 'Show All';
    }

    get hasDirectReports() {
        return this.profile.directReports && this.profile.directReports.length > 0;
    }

    get hasRecentActivities() {
        return this.profile.recentActivities && this.profile.recentActivities.length > 0;
    }

    get formattedLastActivity() {
        if (!this.profile.lastActivityDate) return 'No recent activity';
        const date = new Date(this.profile.lastActivityDate);
        return date.toLocaleDateString();
    }

    handleToggleOpportunities() {
        this.showAllOpportunities = !this.showAllOpportunities;
    }

    handleOpportunityClick(event) {
        const oppId = event.currentTarget.dataset.oppId;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: oppId,
                objectApiName: 'Opportunity',
                actionName: 'view'
            }
        });
    }

    handleContactClick(event) {
        const contactId = event.currentTarget.dataset.contactId;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: contactId,
                objectApiName: 'Contact',
                actionName: 'view'
            }
        });
    }

    handleAccountClick() {
        if (this.profile.accountId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.profile.accountId,
                    objectApiName: 'Account',
                    actionName: 'view'
                }
            });
        }
    }

    formatAmount(amount) {
        if (!amount) return '-';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        }).format(amount);
    }

    formatDate(date) {
        if (!date) return '-';
        return new Date(date).toLocaleDateString();
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