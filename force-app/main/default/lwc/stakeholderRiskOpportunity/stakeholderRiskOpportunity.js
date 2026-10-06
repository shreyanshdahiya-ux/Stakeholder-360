import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRiskSignals from '@salesforce/apex/Stakeholder360Controller.getRiskSignals';
import getOpportunitySignals from '@salesforce/apex/Stakeholder360Controller.getOpportunitySignals';

export default class StakeholderRiskOpportunity extends LightningElement {
    @api recordId;

    risks = [];
    opportunities = [];
    isLoading = true;
    error = null;
    activeTab = 'risks';

    connectedCallback() {
        this.loadData();
    }

    async loadData() {
        this.isLoading = true;
        try {
            const [risksData, oppsData] = await Promise.all([
                getRiskSignals({ accountId: this.recordId }),
                getOpportunitySignals({ accountId: this.recordId })
            ]);
            this.error = null;
            this.risks = risksData.map((r, idx) => ({
                ...r,
                key: 'risk-' + idx,
                severityClass: this.getSeverityClass(r.severity),
                categoryIcon: this.getCategoryIcon(r.category)
            }));
            this.opportunities = oppsData.map((o, idx) => ({
                ...o,
                key: 'opp-' + idx,
                impactClass: this.getImpactClass(o.impact)
            }));
        } catch (error) {
            this.error = error?.body?.message || error?.message || 'Failed to load data';
            this.risks = [];
            this.opportunities = [];
            this.showError('Error loading data', error);
        }
        this.isLoading = false;
    }

    get hasError() {
        return !!this.error;
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    get isRisksTab() {
        return this.activeTab === 'risks';
    }

    get isOpportunitiesTab() {
        return this.activeTab === 'opportunities';
    }

    get risksTabClass() {
        return this.isRisksTab ? 'tab-btn active' : 'tab-btn';
    }

    get opportunitiesTabClass() {
        return this.isOpportunitiesTab ? 'tab-btn active' : 'tab-btn';
    }

    get hasRisks() {
        return this.risks && this.risks.length > 0;
    }

    get hasOpportunities() {
        return this.opportunities && this.opportunities.length > 0;
    }

    get riskCount() {
        return this.risks ? this.risks.length : 0;
    }

    get opportunityCount() {
        return this.opportunities ? this.opportunities.length : 0;
    }

    get highRiskCount() {
        return this.risks.filter(r => r.severity === 'High').length;
    }

    get formattedRisks() {
        return this.risks;
    }

    get formattedOpportunities() {
        return this.opportunities;
    }

    getSeverityClass(severity) {
        if (severity === 'High') return 'severity-badge severity-high';
        if (severity === 'Medium') return 'severity-badge severity-medium';
        return 'severity-badge severity-low';
    }

    getImpactClass(impact) {
        if (impact === 'High') return 'impact-badge impact-high';
        if (impact === 'Medium') return 'impact-badge impact-medium';
        return 'impact-badge impact-low';
    }

    getCategoryIcon(category) {
        const icons = {
            'blocker': '🚫',
            'sentiment': '😟',
            'coverage': '📊',
            'engagement': '📅',
            'competitor': '⚔️',
            'political': '🏛️'
        };
        return icons[category] || '⚠️';
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