import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { loadStyle, loadScript } from 'lightning/platformResourceLoader';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import OPPORTUNITY_ACCOUNT_ID from '@salesforce/schema/Opportunity.AccountId';
import jsMind from '@salesforce/resourceUrl/jsmind';
import getRelationshipGraphData from '@salesforce/apex/Stakeholder360Controller.getRelationshipGraphData';

export default class StakeholderGraph extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    @track graphData = null;
    @track isLoading = true;
    @track _accountId;

    scriptsLoaded = false;
    jm = null;
    wiredGraphResult;

    @wire(getRecord, { recordId: '$recordId', optionalFields: [OPPORTUNITY_ACCOUNT_ID] })
    wiredRecord({ data, error }) {
        if (data) {
            const opportunityAccountId = getFieldValue(data, OPPORTUNITY_ACCOUNT_ID);
            this._accountId = opportunityAccountId || this.recordId;
        }
        if (error) {
            this._accountId = this.recordId;
        }
    }

    @wire(getRelationshipGraphData, { accountId: '$_accountId' })
    wiredGraph(result) {
        this.wiredGraphResult = result;
        const { data, error } = result;

        if (data) {
            this.graphData = data;
            this.isLoading = false;
            setTimeout(() => { this.renderMindMap(); }, 100);
        } else if (error) {
            this.showToast('Error', 'Failed to load relationship graph', 'error');
            this.isLoading = false;
        }
    }

    renderedCallback() {
        if (this.scriptsLoaded) return;

        Promise.all([
            loadStyle(this, jsMind + '/jsmind.css'),
            loadScript(this, jsMind + '/jsmind.js')
        ])
            .then(() => {
                this.scriptsLoaded = true;
                this.renderMindMap();
            })
            .catch(() => {
                this.showToast('Error', 'Failed to load jsMind library', 'error');
            });
    }

    renderMindMap() {
        if (!this.scriptsLoaded || this.isLoading || !this.graphData) return;

        const container = this.template.querySelector('.jsmind-container');
        if (!container) return;

        if (!window.jsMind) {
            this.showToast('Error', 'jsMind library not loaded', 'error');
            return;
        }

        try {
            this.jm = null;
            container.replaceChildren();

            const mindData = this.buildMindMapData();

            const options = {
                container,
                theme: 'primary',
                editable: false,
                mode: 'full',
                view: {
                    hmargin: 120,
                    vmargin: 80,
                    line_width: 2,
                    line_color: '#0176d3',
                    draggable: true,
                    hide_scrollbars_when_draggable: false
                },
                layout: { hspace: 80, vspace: 20, pspace: 13 }
            };

            this.jm = new window.jsMind(options);
            this.jm.show(mindData);

            // Pre-render trick: contacts start expanded so jsMind renders their
            // full subtree (honoring expanded:true on Opportunities wrapper).
            // Then collapse each contact so the graph starts clean.
            this.graphData.contacts.forEach(contact => {
                const node = this.jm.get_node(`contact_${contact.contactId}`);
                if (node) this.jm.collapse_node(node);
            });

            this.addNodeClickHandlers();
        } catch (error) {
            this.showToast('Error', 'Failed to render mind map', 'error');
        }
    }

    // Build a lookup: contactId → [{toContactName, relationshipType, strength, direction}]
    buildRelationshipMap() {
        const map = {};
        if (!this.graphData.relationships) return map;

        this.graphData.relationships.forEach(r => {
            // From side
            if (!map[r.fromContactId]) map[r.fromContactId] = [];
            map[r.fromContactId].push({
                toName:           r.toContactName,
                relationshipType: r.relationshipType,
                strength:         r.strength,
                direction:        r.direction
            });

            // Mutual — also show from the other side
            if (r.direction !== 'One Way (A to B)') {
                if (!map[r.toContactId]) map[r.toContactId] = [];
                map[r.toContactId].push({
                    toName:           r.fromContactName,
                    relationshipType: r.relationshipType,
                    strength:         r.strength,
                    direction:        r.direction
                });
            }
        });

        return map;
    }

    buildMindMapData() {
        const relMap = this.buildRelationshipMap();

        const data = {
            meta: { name: 'Relationship Graph', version: '1.0' },
            format: 'node_tree',
            data: {
                id: 'root',
                topic: this.escapeHtml(this.graphData.accountName),
                expanded: true,
                'background-color': '#0176d3',
                'foreground-color': '#ffffff',
                children: []
            }
        };

        // Contacts branch (right side)
        if (this.graphData.contacts && this.graphData.contacts.length > 0) {
            const contactsNode = {
                id: 'contacts',
                topic: `Contacts (${this.graphData.totalContacts})`,
                expanded: true,
                direction: 'right',
                'background-color': '#3b82f6',
                'foreground-color': '#ffffff',
                children: []
            };

            this.graphData.contacts.forEach((contact) => {
                const contactNode = {
                    id: `contact_${contact.contactId}`,
                    topic: this.escapeHtml(
                        `${contact.contactName}${contact.title ? ' – ' + contact.title : ''}`
                    ),
                    expanded: true,
                    'background-color': '#60a5fa',
                    'foreground-color': '#ffffff',
                    data: { type: 'contact', recordId: contact.contactId },
                    children: []
                };

                // Opportunities wrapper — expanded:true so names show on first expand
                if (contact.opportunities && contact.opportunities.length > 0) {
                    contactNode.children.push({
                        id: `contact_${contact.contactId}_opps`,
                        topic: `Opportunities (${contact.opportunities.length})`,
                        expanded: true,
                        'background-color': '#fbbf24',
                        'foreground-color': '#78350f',
                        children: contact.opportunities.map((opp) => ({
                            id: `opp_${contact.contactId}_${opp.opportunityId}`,
                            topic: this.escapeHtml(
                                `${opp.opportunityName} – ${opp.stageName}` +
                                (opp.amount ? ' – ' + this.formatCurrency(opp.amount) : '')
                            ),
                            'background-color': '#fde68a',
                            'foreground-color': '#92400e',
                            data: { type: 'opportunity', recordId: opp.opportunityId }
                        }))
                    });
                }

                // Cases wrapper
                if (contact.cases && contact.cases.length > 0) {
                    contactNode.children.push({
                        id: `contact_${contact.contactId}_cases`,
                        topic: `Cases (${contact.cases.length})`,
                        expanded: true,
                        'background-color': '#ef4444',
                        'foreground-color': '#ffffff',
                        children: contact.cases.map((c) => ({
                            id: `case_${contact.contactId}_${c.caseId}`,
                            topic: this.escapeHtml(`${c.caseNumber} – ${c.status}`),
                            'background-color': '#fca5a5',
                            'foreground-color': '#7f1d1d',
                            data: { type: 'case', recordId: c.caseId }
                        }))
                    });
                }

                // ── Relationships sub-node (NEW) ───────────────────────────
                const rels = relMap[contact.contactId] || [];
                if (rels.length > 0) {
                    contactNode.children.push({
                        id: `contact_${contact.contactId}_rels`,
                        topic: `Relationships (${rels.length})`,
                        expanded: true,
                        'background-color': '#7c3aed',
                        'foreground-color': '#ffffff',
                        children: rels.map((r, i) => {
                            const arrow = r.direction === 'One Way (A to B)' ? '→' : '↔';
                            const stars = '★'.repeat(r.strength) + '☆'.repeat(5 - r.strength);
                            return {
                                id: `rel_${contact.contactId}_${i}`,
                                topic: this.escapeHtml(
                                    `${arrow} ${r.toName}: ${r.relationshipType} ${stars}`
                                ),
                                'background-color': '#ddd6fe',
                                'foreground-color': '#4c1d95'
                            };
                        })
                    });
                }

                contactsNode.children.push(contactNode);
            });

            data.data.children.push(contactsNode);
        }

        // Account Opportunities branch (left side)
        if (this.graphData.accountOpportunities && this.graphData.accountOpportunities.length > 0) {
            data.data.children.push({
                id: 'account_opps',
                topic: `Account Opportunities (${this.graphData.accountOpportunities.length})`,
                expanded: false,
                direction: 'left',
                'background-color': '#fbbf24',
                'foreground-color': '#78350f',
                children: this.graphData.accountOpportunities.map((opp, i) => ({
                    id: `acc_opp_${opp.opportunityId}_${i}`,
                    topic: this.escapeHtml(
                        `${opp.opportunityName} – ${opp.stageName}` +
                        (opp.amount ? ' – ' + this.formatCurrency(opp.amount) : '')
                    ),
                    'background-color': '#fde68a',
                    'foreground-color': '#92400e',
                    data: { type: 'opportunity', recordId: opp.opportunityId }
                }))
            });
        }

        // Account Cases branch (left side)
        if (this.graphData.accountCases && this.graphData.accountCases.length > 0) {
            data.data.children.push({
                id: 'account_cases',
                topic: `Account Cases (${this.graphData.accountCases.length})`,
                expanded: false,
                direction: 'left',
                'background-color': '#ef4444',
                'foreground-color': '#ffffff',
                children: this.graphData.accountCases.map((c, i) => ({
                    id: `acc_case_${c.caseId}_${i}`,
                    topic: this.escapeHtml(`${c.caseNumber} – ${c.status}`),
                    'background-color': '#fca5a5',
                    'foreground-color': '#7f1d1d',
                    data: { type: 'case', recordId: c.caseId }
                }))
            });
        }

        return data;
    }

    addNodeClickHandlers() {
        const container = this.template.querySelector('.jsmind-container');
        if (!container) return;

        container.addEventListener('click', (event) => {
            const jmnode = event.target.closest('jmnode');
            if (jmnode) {
                const nodeId = jmnode.getAttribute('nodeid');
                if (nodeId && this.jm) {
                    const node = this.jm.get_node(nodeId);
                    if (node && node.data) {
                        this.handleNodeClick(node.data.type, node.data.recordId);
                    } else if (nodeId === 'root') {
                        this.handleNodeClick('account', this.recordId);
                    }
                }
            }
        });
    }

    handleNodeClick(type, recordId) {
        if (!recordId) return;
        const objectApiName = type === 'contact'     ? 'Contact'
                            : type === 'opportunity' ? 'Opportunity'
                            : type === 'case'        ? 'Case'
                            : 'Account';
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName, actionName: 'view' }
        });
    }

    handleExpandAll()  { if (this.jm) this.jm.expand_all(); }
    handleCollapseAll() { if (this.jm) this.jm.collapse_all(); }
    handleZoomIn()     { if (this.jm) this.jm.view.zoom_in(); }
    handleZoomOut()    { if (this.jm) this.jm.view.zoom_out(); }
    handleZoomReset()  { if (this.jm) this.jm.view.set_zoom(1); }

    async handleRefresh() {
        this.isLoading = true;
        try {
            await refreshApex(this.wiredGraphResult);
            this.showToast('Success', 'Relationship graph refreshed', 'success');
        } catch (error) {
            this.showToast('Error', 'Failed to refresh graph', 'error');
            this.isLoading = false;
        }
    }

    formatCurrency(amount) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency', currency: 'USD',
            minimumFractionDigits: 0, maximumFractionDigits: 0
        }).format(amount);
    }

    escapeHtml(text) {
        if (!text) return '';
        return String(text)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    get hasData() {
        return this.graphData && (
            this.graphData.totalContacts > 0 ||
            this.graphData.totalOpportunities > 0 ||
            this.graphData.totalCases > 0
        );
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}