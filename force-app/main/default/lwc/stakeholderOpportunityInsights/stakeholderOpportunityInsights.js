import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOpportunityInsights from '@salesforce/apex/StakeholderOpportunityController.getOpportunityInsights';

export default class StakeholderOpportunityInsights extends NavigationMixin(LightningElement) {
    @api recordId;

    insights = {};
    isLoading = true;
    showAllStakeholders = false;

    @wire(getOpportunityInsights, { opportunityId: '$recordId' })
    wiredInsights({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.insights = {
                ...data,
                stakeholders: (data.stakeholders || []).map(s => ({
                    ...s,
                    roleIcon: this.getRoleIcon(s.role)
                }))
            };
        } else if (error) {
            this.showError('Error loading insights', error);
        }
    }

    get hasInsights() {
        return this.insights && this.insights.opportunityName;
    }

    get overallHealth() {
        if (!this.hasInsights) return 0;
        const coverage = this.insights.coverageHealth || 0;
        const relationship = this.insights.relationshipHealth || 0;
        const engagement = this.insights.engagementHealth || 0;
        return Math.round((coverage + relationship + engagement) / 3);
    }

    get healthStatus() {
        const health = this.overallHealth;
        if (health >= 80) return 'Excellent';
        if (health >= 60) return 'Good';
        if (health >= 40) return 'Fair';
        return 'Needs Attention';
    }

    get healthClass() {
        const health = this.overallHealth;
        if (health >= 80) return 'health-excellent';
        if (health >= 60) return 'health-good';
        if (health >= 40) return 'health-fair';
        return 'health-poor';
    }

    get hasKeyRoleGaps() {
        if (!this.hasInsights) return false;
        return this.insights.championCount === 0 ||
               this.insights.decisionMakerCount === 0 ||
               this.insights.economicBuyerCount === 0;
    }

    get hasStakeholders() {
        return this.insights.stakeholders && this.insights.stakeholders.length > 0;
    }

    get displayedStakeholders() {
        if (!this.hasStakeholders) return [];
        return this.showAllStakeholders ?
            this.insights.stakeholders :
            this.insights.stakeholders.slice(0, 6);
    }

    get showToggleButton() {
        return this.hasStakeholders && this.insights.stakeholders.length > 6;
    }

    get toggleButtonLabel() {
        return this.showAllStakeholders ? 'Show Less' : 'Show All';
    }

    get hasInsightMessages() {
        return this.insights.insights && this.insights.insights.length > 0;
    }

    get insightItems() {
        if (!this.insights.insights) return [];
        return this.insights.insights.map((msg, i) => ({ id: i, message: msg }));
    }

    get strengthStars() {
        if (!this.hasInsights) return [];
        const strength = Math.round(this.insights.averageRelationshipStrength || 0);
        return Array(5).fill(0).map((_, i) => ({
            id: i,
            iconName: 'utility:favorite',
            starClass: i < strength ? 'star-filled' : 'star-empty'
        }));
    }

    handleToggleStakeholders() {
        this.showAllStakeholders = !this.showAllStakeholders;
    }

    handleStakeholderClick(event) {
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

    getRoleIcon(role) {
        const iconMap = {
            'Champion':       'standard:contact',
            'Decision Maker': 'standard:person_account',
            'Economic Buyer': 'standard:opportunity',
            'Business User':  'standard:account',
            'Technical Buyer':'standard:pricebook',
            'Evaluator':      'standard:task',
            'Influencer':     'standard:relationship',
            'Gatekeeper':     'standard:case'
        };
        return iconMap[role] || 'standard:contact';
    }

    getRoleColor(role) {
        const colorMap = {
            'Champion': 'color-champion',
            'Decision Maker': 'color-decision',
            'Economic Buyer': 'color-economic',
            'Business User': 'color-business',
            'Evaluator': 'color-evaluator',
            'Influencer': 'color-influencer'
        };
        return colorMap[role] || 'color-default';
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