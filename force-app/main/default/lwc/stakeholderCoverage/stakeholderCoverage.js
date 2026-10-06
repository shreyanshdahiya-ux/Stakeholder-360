import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCoverageAnalysis from '@salesforce/apex/Stakeholder360Controller.getCoverageAnalysis';

export default class StakeholderCoverage extends LightningElement {
    @api recordId;

    coverage = {};
    isLoading = true;

    @wire(getCoverageAnalysis, { accountId: '$recordId' })
    wiredCoverage({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.coverage = data;
        } else if (error) {
            this.coverage = {};
            this.showError('Error loading coverage analysis', error);
        }
    }

    get hasData() {
        return this.coverage && this.coverage.requiredRoles !== undefined;
    }

    get coveragePercentage() {
        return this.hasData ? this.coverage.coveragePercentage : 0;
    }

    // Circular progress ring
    get ringClass() {
        if (!this.hasData) return 'ring-progress';
        const pct = this.coverage.coveragePercentage;
        if (pct >= 80) return 'ring-excellent';
        if (pct >= 60) return 'ring-good';
        if (pct >= 40) return 'ring-fair';
        return 'ring-critical';
    }

    get ringStyle() {
        const circumference = 339.292; // 2 * PI * 54
        const percentage = this.hasData ? this.coverage.coveragePercentage : 0;
        const offset = circumference - (percentage / 100) * circumference;
        return `stroke-dashoffset: ${offset}`;
    }

    get statusClass() {
        if (!this.hasData) return 'status-pill';
        const status = this.coverage.coverageStatus;
        if (status === 'Excellent') return 'status-pill status-excellent';
        if (status === 'Good') return 'status-pill status-good';
        if (status === 'Fair') return 'status-pill status-fair';
        return 'status-pill status-critical';
    }

    // Role cards
    get decisionMakerClass() {
        return this.coverage.hasDecisionMaker ? 'role-card role-covered' : 'role-card role-missing';
    }

    get economicBuyerClass() {
        return this.coverage.hasEconomicBuyer ? 'role-card role-covered' : 'role-card role-missing';
    }

    get technicalBuyerClass() {
        return this.coverage.hasTechnicalBuyer ? 'role-card role-covered' : 'role-card role-missing';
    }

    get championClass() {
        return this.coverage.hasChampion ? 'role-card role-covered' : 'role-card role-missing';
    }

    get influencerClass() {
        return this.coverage.hasInfluencer ? 'role-card role-covered' : 'role-card role-missing';
    }

    get userClass() {
        return this.coverage.hasUser ? 'role-card role-covered' : 'role-card role-missing';
    }

    get decisionMakerIcon() {
        return this.coverage.hasDecisionMaker ? '✅' : '❌';
    }

    get economicBuyerIcon() {
        return this.coverage.hasEconomicBuyer ? '✅' : '❌';
    }

    get technicalBuyerIcon() {
        return this.coverage.hasTechnicalBuyer ? '✅' : '❌';
    }

    get championIcon() {
        return this.coverage.hasChampion ? '✅' : '❌';
    }

    get influencerIcon() {
        return this.coverage.hasInfluencer ? '✅' : '❌';
    }

    get userIcon() {
        return this.coverage.hasUser ? '✅' : '❌';
    }

    get hasMissingRoles() {
        return this.coverage.missingRoles && this.coverage.missingRoles.length > 0;
    }

    get missingRolesFormatted() {
        if (!this.hasMissingRoles) return [];
        return this.coverage.missingRoles.map(role => ({ role }));
    }

    get hasBlockerWarning() {
        return this.coverage.hasBlocker;
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