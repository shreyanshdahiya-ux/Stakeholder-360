import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getStakeholderTreeData from '@salesforce/apex/Stakeholder360Controller.getStakeholderTreeData';

export default class StakeholderMindMap extends NavigationMixin(LightningElement) {
    @api recordId;

    @track treeData = null;
    @track isLoading = true;
    @track error = null;

    // Toggle states for role categories
    @track showChampions = true;
    @track showDecisionMakers = true;
    @track showInfluencers = true;
    @track showBlockers = true;
    @track showOthers = true;

    // Toggle states for individual contacts (expand/collapse opportunities)
    @track expandedContacts = new Set();

    wiredTreeResult;

    @wire(getStakeholderTreeData, { accountId: '$recordId' })
    wiredTree(result) {
        this.wiredTreeResult = result;
        const { data, error } = result;

        if (data) {
            this.treeData = this.processTreeData(data);
            this.error = null;
            this.isLoading = false;
        } else if (error) {
            this.error = error?.body?.message || error?.message || 'Failed to load stakeholder tree';
            this.showToast('Error', this.error, 'error');
            this.isLoading = false;
        }
    }

    processTreeData(data) {
        // Process each contact to add computed properties
        const processContacts = (contacts) => {
            return contacts.map(contact => {
                const isExpanded = this.expandedContacts.has(contact.contactId);
                return {
                    ...contact,
                    initials: this.getInitials(contact.contactName),
                    hasOpportunities: contact.opportunities && contact.opportunities.length > 0,
                    isExpanded: isExpanded,
                    expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                    rolesDisplay: contact.roles ? contact.roles.join(', ') : '',
                    opportunities: contact.opportunities ? contact.opportunities.map(opp => ({
                        ...opp,
                        formattedAmount: opp.amount ? this.formatCurrency(opp.amount) : '',
                        formattedCloseDate: opp.closeDate ? this.formatDate(opp.closeDate) : ''
                    })) : []
                };
            });
        };

        return {
            ...data,
            champions: processContacts(data.champions || []),
            decisionMakers: processContacts(data.decisionMakers || []),
            influencers: processContacts(data.influencers || []),
            blockers: processContacts(data.blockers || []),
            others: processContacts(data.others || [])
        };
    }

    getInitials(name) {
        if (!name) return '?';
        const parts = name.split(' ');
        if (parts.length >= 2) {
            return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
        }
        return name.substring(0, 2).toUpperCase();
    }

    formatCurrency(amount) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        }).format(amount);
    }

    formatDate(dateStr) {
        if (!dateStr) return '';
        const date = new Date(dateStr);
        return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
    }

    // Computed Properties
    get hasError() {
        return !!this.error;
    }

    get hasData() {
        return this.treeData && this.treeData.totalContacts > 0;
    }

    get showEmptyState() {
        return !this.hasError && !this.hasData;
    }

    get accountName() {
        return this.treeData?.accountName || 'Account';
    }

    get totalContacts() {
        return this.treeData?.totalContacts || 0;
    }

    // Champions
    get champions() {
        return this.treeData?.champions || [];
    }

    get hasChampions() {
        return this.champions.length > 0;
    }

    get championCount() {
        return this.champions.length;
    }

    // Decision Makers
    get decisionMakers() {
        return this.treeData?.decisionMakers || [];
    }

    get hasDecisionMakers() {
        return this.decisionMakers.length > 0;
    }

    get decisionMakerCount() {
        return this.decisionMakers.length;
    }

    // Influencers
    get influencers() {
        return this.treeData?.influencers || [];
    }

    get hasInfluencers() {
        return this.influencers.length > 0;
    }

    get influencerCount() {
        return this.influencers.length;
    }

    // Blockers
    get blockers() {
        return this.treeData?.blockers || [];
    }

    get hasBlockers() {
        return this.blockers.length > 0;
    }

    get blockerCount() {
        return this.blockers.length;
    }

    // Others
    get others() {
        return this.treeData?.others || [];
    }

    get hasOthers() {
        return this.others.length > 0;
    }

    get otherCount() {
        return this.others.length;
    }

    // Expand/Collapse Icons
    get championsExpandIcon() {
        return this.showChampions ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get decisionMakersExpandIcon() {
        return this.showDecisionMakers ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get influencersExpandIcon() {
        return this.showInfluencers ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get blockersExpandIcon() {
        return this.showBlockers ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get othersExpandIcon() {
        return this.showOthers ? 'utility:chevrondown' : 'utility:chevronright';
    }

    // Event Handlers - Toggle Category Branches
    toggleChampions() {
        this.showChampions = !this.showChampions;
    }

    toggleDecisionMakers() {
        this.showDecisionMakers = !this.showDecisionMakers;
    }

    toggleInfluencers() {
        this.showInfluencers = !this.showInfluencers;
    }

    toggleBlockers() {
        this.showBlockers = !this.showBlockers;
    }

    toggleOthers() {
        this.showOthers = !this.showOthers;
    }

    // Toggle contact expansion to show/hide opportunities
    toggleContactExpand(event) {
        event.stopPropagation();
        const contactId = event.currentTarget.dataset.contactId;

        if (this.expandedContacts.has(contactId)) {
            this.expandedContacts.delete(contactId);
        } else {
            this.expandedContacts.add(contactId);
        }

        if (this.treeData && this.wiredTreeResult?.data) {
            this.treeData = this.processTreeData(this.wiredTreeResult.data);
        }
    }

    // Event Handlers - Expand/Collapse All
    handleExpandAll() {
        this.showChampions = true;
        this.showDecisionMakers = true;
        this.showInfluencers = true;
        this.showBlockers = true;
        this.showOthers = true;

        // Expand all contacts
        if (this.treeData && this.wiredTreeResult?.data) {
            const allContactIds = [
                ...this.champions,
                ...this.decisionMakers,
                ...this.influencers,
                ...this.blockers,
                ...this.others
            ].map(c => c.contactId);

            this.expandedContacts = new Set(allContactIds);
            this.treeData = this.processTreeData(this.wiredTreeResult.data);
        }
    }

    handleCollapseAll() {
        this.showChampions = false;
        this.showDecisionMakers = false;
        this.showInfluencers = false;
        this.showBlockers = false;
        this.showOthers = false;

        // Collapse all contacts
        this.expandedContacts = new Set();
        if (this.treeData && this.wiredTreeResult?.data) {
            this.treeData = this.processTreeData(this.wiredTreeResult.data);
        }
    }

    // Event Handlers - Navigation
    handleAccountClick() {
        if (this.recordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.recordId,
                    objectApiName: 'Account',
                    actionName: 'view'
                }
            });
        }
    }

    handleContactClick(event) {
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

    handleOpportunityClick(event) {
        event.stopPropagation();
        const opportunityId = event.currentTarget.dataset.opportunityId;
        if (opportunityId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: opportunityId,
                    objectApiName: 'Opportunity',
                    actionName: 'view'
                }
            });
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
}