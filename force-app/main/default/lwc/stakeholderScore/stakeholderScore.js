import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import calculateScore from '@salesforce/apex/StakeholderChartController.calculateScore';

export default class StakeholderScore extends LightningElement {
    @api recordId;

    score = {};
    isLoading = true;
    error;

    @wire(calculateScore, { opportunityId: '$recordId' })
    wiredScore({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.score = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.score = {};
            this.showError('Error loading stakeholder score', error);
        }
    }

    get hasData() {
        return this.score && this.score.totalStakeholders !== undefined;
    }

    get overallScorePercentage() {
        return this.hasData ? this.score.overallScore : 0;
    }

    // Health Status
    get healthStatus() {
        if (!this.hasData) return 'Unknown';
        const score = this.score.overallScore;
        if (score >= 80) return 'Excellent';
        if (score >= 60) return 'Good';
        if (score >= 40) return 'Fair';
        return 'Needs Attention';
    }

    get healthPillClass() {
        if (!this.hasData) return 'health-pill';
        const score = this.score.overallScore;
        if (score >= 80) return 'health-pill health-excellent';
        if (score >= 60) return 'health-pill health-good';
        if (score >= 40) return 'health-pill health-fair';
        return 'health-pill health-poor';
    }

    // Circular Score Ring
    get scoreRingClass() {
        if (!this.hasData) return 'score-ring-progress';
        const score = this.score.overallScore;
        if (score >= 80) return 'score-ring-high';
        if (score >= 50) return 'score-ring-medium';
        return 'score-ring-low';
    }

    get scoreRingStyle() {
        const circumference = 339.292; // 2 * PI * 54
        const percentage = this.hasData ? this.score.overallScore : 0;
        const offset = circumference - (percentage / 100) * circumference;
        return `stroke-dashoffset: ${offset}`;
    }

    get scoreValueClass() {
        if (!this.hasData) return 'score-value';
        const score = this.score.overallScore;
        if (score >= 80) return 'score-value-high';
        if (score >= 50) return 'score-value-medium';
        return 'score-value-low';
    }

    get scoreDescription() {
        if (!this.hasData) return '';
        const score = this.score.overallScore;
        if (score >= 80) return 'Excellent stakeholder coverage and engagement';
        if (score >= 60) return 'Good progress, some areas to improve';
        if (score >= 40) return 'Moderate coverage, needs attention';
        return 'Critical gaps in stakeholder engagement';
    }

    // Progress Bar Styles
    get coverageScorePercentage() {
        return this.hasData ? Math.round((this.score.coverageScore / 70) * 100) : 0;
    }

    get relationshipScorePercentage() {
        return this.hasData ? Math.round((this.score.relationshipScore / 15) * 100) : 0;
    }

    get engagementScorePercentage() {
        return this.hasData ? Math.round((this.score.engagementScore / 15) * 100) : 0;
    }

    get coverageBarStyle() {
        return `width: ${this.coverageScorePercentage}%`;
    }

    get relationshipBarStyle() {
        return `width: ${this.relationshipScorePercentage}%`;
    }

    get engagementBarStyle() {
        return `width: ${this.engagementScorePercentage}%`;
    }

    // Role Cards
    get championRoleClass() {
        return this.score.hasChampion ? 'role-card-active' : 'role-card-inactive';
    }

    get decisionMakerRoleClass() {
        return this.score.hasDecisionMaker ? 'role-card-active' : 'role-card-inactive';
    }

    get budgetHolderRoleClass() {
        return this.score.hasBudgetHolder ? 'role-card-active' : 'role-card-inactive';
    }

    get championIcon() {
        return this.score.hasChampion ? '✅' : '❌';
    }

    get decisionMakerIcon() {
        return this.score.hasDecisionMaker ? '✅' : '❌';
    }

    get budgetHolderIcon() {
        return this.score.hasBudgetHolder ? '✅' : '❌';
    }

    // Recommendations
    get hasRecommendations() {
        return this.recommendations && this.recommendations.length > 0;
    }

    get recommendations() {
        const texts = [];
        if (!this.hasData) return texts;

        if (!this.score.hasChampion) {
            texts.push('Identify and engage a Champion within the organization');
        }
        if (!this.score.hasDecisionMaker) {
            texts.push('Connect with the Decision Maker to understand their priorities');
        }
        if (!this.score.hasBudgetHolder) {
            texts.push('Engage with the Economic Buyer to discuss budget and ROI');
        }
        if (this.score.totalStakeholders < 3) {
            texts.push('Expand stakeholder coverage - aim for at least 3 key contacts');
        }
        if (this.score.engagementScore < 10) {
            texts.push('Increase engagement frequency with key stakeholders');
        }

        return texts.map((text, i) => ({ id: i, text }));
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