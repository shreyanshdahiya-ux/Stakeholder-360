import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAccountStakeholders from '@salesforce/apex/Stakeholder360Controller.getAccountStakeholders';

const COLUMNS = [
    {
        label: 'Name',
        fieldName: 'contactUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'contactName' },
            target: '_blank'
        },
        sortable: true
    },
    {
        label: 'Title',
        fieldName: 'title',
        type: 'text',
        sortable: true
    },
    {
        label: 'Role',
        fieldName: 'role',
        type: 'text',
        sortable: true,
        cellAttributes: {
            class: { fieldName: 'roleClass' }
        }
    },
    {
        label: 'Influence',
        fieldName: 'influenceLevel',
        type: 'text',
        sortable: true,
        cellAttributes: {
            class: { fieldName: 'influenceClass' }
        }
    },
    {
        label: 'Decision Power',
        fieldName: 'decisionPower',
        type: 'text',
        sortable: true
    },
    {
        label: 'Sentiment',
        fieldName: 'sentiment',
        type: 'text',
        sortable: true,
        cellAttributes: {
            class: { fieldName: 'sentimentClass' }
        }
    },
    {
        label: 'Engagement',
        fieldName: 'engagementLevel',
        type: 'text',
        sortable: true
    },
    {
        label: 'Priority',
        fieldName: 'priorityScore',
        type: 'number',
        sortable: true,
        cellAttributes: {
            class: { fieldName: 'priorityClass' }
        }
    },
    {
        label: 'Risk',
        fieldName: 'riskDisplay',
        type: 'text',
        sortable: true,
        cellAttributes: {
            class: { fieldName: 'riskClass' }
        }
    },
    {
        label: 'Last Engaged',
        fieldName: 'lastEngagementDate',
        type: 'date',
        sortable: true,
        typeAttributes: {
            month: 'short',
            day: '2-digit',
            year: 'numeric'
        }
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'View', name: 'view' },
                { label: 'Edit', name: 'edit' },
                { label: 'Log Activity', name: 'log_activity' }
            ]
        }
    }
];

export default class StakeholderList extends LightningElement {
    @api recordId;

    @track stakeholders = [];
    @track isLoading = true;
    @track error = null;

    // Filter states
    @track searchTerm = '';
    @track selectedRole = '';
    @track selectedSentiment = '';
    @track selectedInfluence = '';
    @track selectedRisk = '';

    // Sort states
    @track sortedBy = 'priorityScore';
    @track sortedDirection = 'desc';

    // Modal states
    @track showEditModal = false;
    @track editStakeholderId = null;

    columns = COLUMNS;
    wiredStakeholderResult;

    @wire(getAccountStakeholders, { accountId: '$recordId' })
    wiredStakeholders(result) {
        this.wiredStakeholderResult = result;
        const { data, error } = result;

        if (data) {
            this.stakeholders = data.map(s => this.processStakeholder(s));
            this.error = null;
            this.isLoading = false;
        } else if (error) {
            this.error = error?.body?.message || error?.message || 'Failed to load stakeholders';
            this.stakeholders = [];
            this.showToast('Error', this.error, 'error');
            this.isLoading = false;
        }
    }

    processStakeholder(s) {
        return {
            ...s,
            contactUrl: `/lightning/r/Contact/${s.contactId}/view`,
            riskDisplay: s.riskFlag ? 'At Risk' : 'OK',
            roleClass: this.getRoleClass(s.role),
            influenceClass: this.getInfluenceClass(s.influenceLevel),
            sentimentClass: this.getSentimentClass(s.sentiment),
            priorityClass: this.getPriorityClass(s.priorityScore),
            riskClass: s.riskFlag ? 'slds-text-color_error' : 'slds-text-color_success'
        };
    }

    getRoleClass(role) {
        if (role === 'Champion' || role === 'Executive Sponsor') return 'slds-text-color_success';
        if (role === 'Blocker') return 'slds-text-color_error';
        return '';
    }

    getInfluenceClass(influence) {
        if (influence === 'High') return 'slds-text-color_error';
        if (influence === 'Medium') return 'slds-text-color_warning';
        return '';
    }

    getSentimentClass(sentiment) {
        if (sentiment === 'Positive') return 'slds-text-color_success';
        if (sentiment === 'Negative') return 'slds-text-color_error';
        return '';
    }

    getPriorityClass(score) {
        if (score >= 7) return 'slds-text-color_success';
        if (score <= 3) return 'slds-text-color_error';
        return '';
    }

    get hasError() {
        return !!this.error;
    }

    // Computed properties
    get filteredStakeholders() {
        let filtered = [...this.stakeholders];

        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            filtered = filtered.filter(s =>
                (s.contactName && s.contactName.toLowerCase().includes(term)) ||
                (s.title && s.title.toLowerCase().includes(term))
            );
        }

        if (this.selectedRole) {
            filtered = filtered.filter(s => s.role === this.selectedRole);
        }

        if (this.selectedSentiment) {
            filtered = filtered.filter(s => s.sentiment === this.selectedSentiment);
        }

        if (this.selectedInfluence) {
            filtered = filtered.filter(s => s.influenceLevel === this.selectedInfluence);
        }

        if (this.selectedRisk === 'at_risk') {
            filtered = filtered.filter(s => s.riskFlag);
        } else if (this.selectedRisk === 'ok') {
            filtered = filtered.filter(s => !s.riskFlag);
        }

        // Apply sorting
        if (this.sortedBy) {
            filtered.sort((a, b) => {
                let valueA = a[this.sortedBy] ?? '';
                let valueB = b[this.sortedBy] ?? '';

                if (typeof valueA === 'string') {
                    valueA = valueA.toLowerCase();
                    valueB = valueB.toLowerCase();
                }

                if (valueA < valueB) return this.sortedDirection === 'asc' ? -1 : 1;
                if (valueA > valueB) return this.sortedDirection === 'asc' ? 1 : -1;
                return 0;
            });
        }

        return filtered;
    }

    get hasStakeholders() {
        return this.filteredStakeholders && this.filteredStakeholders.length > 0;
    }

    get totalCount() {
        return this.stakeholders.length;
    }

    get championCount() {
        return this.stakeholders.filter(s =>
            s.role === 'Champion' || s.role === 'Executive Sponsor'
        ).length;
    }

    get blockerCount() {
        return this.stakeholders.filter(s => s.role === 'Blocker').length;
    }

    get riskCount() {
        return this.stakeholders.filter(s => s.riskFlag).length;
    }

    get modalTitle() {
        return this.editStakeholderId ? 'Edit Stakeholder' : 'New Stakeholder';
    }

    // Filter options
    get roleOptions() {
        return [
            { label: 'All Roles', value: '' },
            { label: 'Champion', value: 'Champion' },
            { label: 'Decision Maker', value: 'Decision Maker' },
            { label: 'Economic Buyer', value: 'Economic Buyer' },
            { label: 'Technical Buyer', value: 'Technical Buyer' },
            { label: 'Influencer', value: 'Influencer' },
            { label: 'Blocker', value: 'Blocker' },
            { label: 'User', value: 'User' },
            { label: 'Executive Sponsor', value: 'Executive Sponsor' },
            { label: 'Gatekeeper', value: 'Gatekeeper' }
        ];
    }

    get sentimentOptions() {
        return [
            { label: 'All Sentiments', value: '' },
            { label: 'Positive', value: 'Positive' },
            { label: 'Neutral', value: 'Neutral' },
            { label: 'Negative', value: 'Negative' }
        ];
    }

    get influenceOptions() {
        return [
            { label: 'All Levels', value: '' },
            { label: 'High', value: 'High' },
            { label: 'Medium', value: 'Medium' },
            { label: 'Low', value: 'Low' }
        ];
    }

    get riskOptions() {
        return [
            { label: 'All', value: '' },
            { label: 'At Risk', value: 'at_risk' },
            { label: 'OK', value: 'ok' }
        ];
    }

    // Event handlers
    handleSearch(event) {
        this.searchTerm = event.detail.value;
    }

    handleRoleFilter(event) {
        this.selectedRole = event.detail.value;
    }

    handleSentimentFilter(event) {
        this.selectedSentiment = event.detail.value;
    }

    handleInfluenceFilter(event) {
        this.selectedInfluence = event.detail.value;
    }

    handleRiskFilter(event) {
        this.selectedRisk = event.detail.value;
    }

    handleClearFilters() {
        this.searchTerm = '';
        this.selectedRole = '';
        this.selectedSentiment = '';
        this.selectedInfluence = '';
        this.selectedRisk = '';
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy = fieldName;
        this.sortedDirection = sortDirection;
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        switch (action.name) {
            case 'view':
                this.navigateToRecord(row.id);
                break;
            case 'edit':
                this.editStakeholderId = row.id;
                this.showEditModal = true;
                break;
            case 'log_activity':
                this.logActivity(row);
                break;
            default:
                break;
        }
    }

    handleNewStakeholder() {
        this.editStakeholderId = null;
        this.showEditModal = true;
    }

    handleCloseModal() {
        this.showEditModal = false;
        this.editStakeholderId = null;
    }

    handleBackdropClick() {
        this.handleCloseModal();
    }

    handleModalKeyDown(event) {
        if (event.key === 'Escape' || event.keyCode === 27) {
            event.preventDefault();
            event.stopPropagation();
            this.handleCloseModal();
        }
    }

    handleStakeholderSaved() {
        this.showEditModal = false;
        this.editStakeholderId = null;
        this.refreshData();
        // Toast is already shown by stakeholderForm component
    }

    // Helper methods
    navigateToRecord(recordId) {
        window.open(`/lightning/r/Stakeholder__c/${recordId}/view`, '_blank');
    }

    logActivity(row) {
        window.open(`/lightning/o/Task/new?defaultFieldValues=WhoId=${row.contactId}`, '_blank');
    }

    async refreshData() {
        this.isLoading = true;
        try {
            await refreshApex(this.wiredStakeholderResult);
        } catch (error) {
            // Silent error handling
        }
        this.isLoading = false;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
}