import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAccountSummary from '@salesforce/apex/StakeholderAccountController.getAccountSummary';
import getKeyContacts from '@salesforce/apex/StakeholderAccountController.getKeyContacts';

export default class StakeholderAccountSummary extends NavigationMixin(LightningElement) {
    @api recordId;

    summary = {};
    contacts = [];
    isLoading = true;
    showContacts = false;

    @wire(getAccountSummary, { accountId: '$recordId' })
    wiredSummary({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.summary = data;
        } else if (error) {
            this.showError('Error loading summary', error);
        }
    }

    @wire(getKeyContacts, { accountId: '$recordId' })
    wiredContacts({ error, data }) {
        if (data) {
            this.contacts = data;
        } else if (error) {
            this.showError('Error loading contacts', error);
        }
    }

    get hasSummary() {
        return this.summary && this.summary.totalContacts !== undefined;
    }

    get hasAccountInfo() {
        return this.summary && this.summary.accountInfo;
    }

    get formattedLocation() {
        if (!this.hasAccountInfo) return '';
        const info = this.summary.accountInfo;
        const parts = [];
        if (info.billingCity) parts.push(info.billingCity);
        if (info.billingState) parts.push(info.billingState);
        if (info.billingCountry) parts.push(info.billingCountry);
        return parts.join(', ');
    }

    get formattedAnnualRevenue() {
        if (!this.hasAccountInfo || !this.summary.accountInfo.annualRevenue) return '';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            notation: 'compact',
            maximumFractionDigits: 1
        }).format(this.summary.accountInfo.annualRevenue);
    }

    get formattedEmployees() {
        if (!this.hasAccountInfo || !this.summary.accountInfo.numberOfEmployees) return '';
        const emp = this.summary.accountInfo.numberOfEmployees;
        if (emp >= 1000) {
            return (emp / 1000).toFixed(1) + 'K';
        }
        return emp.toString();
    }

    get formattedTenure() {
        if (!this.hasAccountInfo || !this.summary.accountInfo.tenureDays) return '';
        const days = this.summary.accountInfo.tenureDays;
        if (days < 30) return `${days} days`;
        if (days < 365) return `${Math.round(days / 30)} months`;
        const years = Math.floor(days / 365);
        const months = Math.round((days % 365) / 30);
        if (months === 0) return `${years} year${years > 1 ? 's' : ''}`;
        return `${years}y ${months}m`;
    }

    get formattedLastActivity() {
        if (!this.hasAccountInfo || this.summary.accountInfo.daysSinceLastActivity === undefined) return '';
        const days = this.summary.accountInfo.daysSinceLastActivity;
        if (days === 0) return 'Today';
        if (days === 1) return 'Yesterday';
        if (days < 7) return `${days} days ago`;
        if (days < 30) return `${Math.round(days / 7)} weeks ago`;
        if (days < 365) return `${Math.round(days / 30)} months ago`;
        return `${Math.round(days / 365)} years ago`;
    }

    get lastActivityClass() {
        if (!this.hasAccountInfo || this.summary.accountInfo.daysSinceLastActivity === undefined) {
            return 'metric-value-small';
        }
        const days = this.summary.accountInfo.daysSinceLastActivity;
        if (days <= 7) return 'metric-value-small activity-recent';
        if (days <= 30) return 'metric-value-small activity-moderate';
        return 'metric-value-small activity-stale';
    }

    get ratingBadgeClass() {
        if (!this.hasAccountInfo || !this.summary.accountInfo.rating) return 'rating-badge';
        const rating = this.summary.accountInfo.rating;
        if (rating === 'Hot') return 'rating-badge rating-hot';
        if (rating === 'Warm') return 'rating-badge rating-warm';
        if (rating === 'Cold') return 'rating-badge rating-cold';
        return 'rating-badge';
    }

    get healthScoreClass() {
        if (!this.hasSummary) return 'summary-header';
        const score = this.summary.healthScore;
        if (score >= 80) return 'summary-header score-excellent';
        if (score >= 60) return 'summary-header score-good';
        if (score >= 40) return 'summary-header score-fair';
        return 'summary-header score-poor';
    }

    get healthStatus() {
        if (!this.hasSummary) return 'Unknown';
        const score = this.summary.healthScore;
        if (score >= 80) return 'Excellent';
        if (score >= 60) return 'Good';
        if (score >= 40) return 'Fair';
        return 'Needs Attention';
    }

    get formattedTotalValue() {
        if (!this.hasSummary || !this.summary.totalValue) return '$0';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        }).format(this.summary.totalValue);
    }

    get strengthStars() {
        if (!this.hasSummary) return [];
        const strength = Math.round(this.summary.averageRelationshipStrength);
        return Array(5).fill(0).map((_, i) => ({
            id: i,
            iconName: i < strength ? 'utility:favorite' : 'utility:favorite_off',
            cssClass: i < strength ? 'star-filled' : 'star-empty'
        }));
    }

    get hasRoleDistribution() {
        return this.summary.roleDistribution && this.summary.roleDistribution.length > 0;
    }

    get topRoles() {
        if (!this.hasRoleDistribution) return [];
        // Create a copy before sorting to avoid mutating LWC proxy
        return [...this.summary.roleDistribution]
            .sort((a, b) => b.count - a.count)
            .slice(0, 5);
    }

    get hasContacts() {
        return this.contacts && this.contacts.length > 0;
    }

    get showMoreButton() {
        return this.contacts && this.contacts.length > 5;
    }

    get displayedContacts() {
        return this.showContacts ? this.contacts : this.contacts.slice(0, 5);
    }

    get showMoreLabel() {
        return this.showContacts ? 'Show Less' : 'Show All';
    }

    handleToggleContacts() {
        this.showContacts = !this.showContacts;
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

    showError(title, error) {
        const message = error?.body?.message || error?.message || 'Unknown error';
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant: 'error'
        }));
    }
}