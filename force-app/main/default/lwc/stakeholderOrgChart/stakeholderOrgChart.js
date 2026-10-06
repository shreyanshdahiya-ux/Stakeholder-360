import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import D3 from '@salesforce/resourceUrl/d3js';
import D3FLEXTREE from '@salesforce/resourceUrl/d3flextree';
import D3ORGCHART from '@salesforce/resourceUrl/d3orgchart';
import getOpportunityChartData from '@salesforce/apex/StakeholderChartController.getOpportunityChartData';
import getAccountContacts from '@salesforce/apex/StakeholderChartController.getAccountContacts';

export default class StakeholderOrgChart extends LightningElement {
    @api recordId;
    @api objectApiName;

    @track stakeholders = [];
    @track accountInfo = null;
    @track opportunityInfo = null;
    @track opportunities = [];
    @track cases = [];
    @track chartLinks = [];
    @track isLoading = true;

    // Filter states
    @track searchTerm = '';
    @track selectedRole = '';

    // Toggle states - default OFF for cleaner view
    @track showOpportunities = false;
    @track showCases = false;

    scriptsLoaded = false;
    dataLoaded = false;
    dataFetched = false;
    chartRendered = false;
    isRendering = false;
    chart = null;

    // Computed properties
    get stakeholderCount() {
        return this.filteredStakeholders.length;
    }

    get filteredStakeholders() {
        let filtered = [...this.stakeholders];

        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            filtered = filtered.filter(s =>
                (s.name && s.name.toLowerCase().includes(term)) ||
                (s.title && s.title.toLowerCase().includes(term))
            );
        }

        if (this.selectedRole) {
            filtered = filtered.filter(s => s.role === this.selectedRole);
        }

        return filtered;
    }

    get roleOptions() {
        const roles = new Set(this.stakeholders.map(s => s.role).filter(r => r));
        const options = [{ label: 'All Roles', value: '' }];
        roles.forEach(role => {
            options.push({ label: role, value: role });
        });
        return options;
    }

    get opportunitiesToggleVariant() {
        return this.showOpportunities ? 'brand' : 'neutral';
    }

    get casesToggleVariant() {
        return this.showCases ? 'brand' : 'neutral';
    }

    get effectiveObjectType() {
        if (this.objectApiName) {
            return this.objectApiName;
        }
        if (this.recordId) {
            const prefix = this.recordId.substring(0, 3);
            if (prefix === '001') return 'Account';
            if (prefix === '006') return 'Opportunity';
        }
        return null;
    }

    connectedCallback() {
        this.loadData();
    }

    async loadData() {
        if (this.dataFetched || !this.recordId) {
            return;
        }

        const objType = this.effectiveObjectType;
        if (!objType) {
            return;
        }

        this.dataFetched = true;
        this.isLoading = true;

        try {
            if (objType === 'Account') {
                await this.loadAccountData();
            } else if (objType === 'Opportunity') {
                await this.loadOpportunityData();
            }
        } catch (error) {
            this.showError('Error loading data', error);
            this.isLoading = false;
        }
    }

    async loadAccountData() {
        try {
            const result = await getAccountContacts({ accountId: this.recordId });

            if (result) {
                this.accountInfo = result.accountInfo;
                this.stakeholders = result.nodes || [];
                this.opportunities = result.opportunities || [];
                this.cases = result.cases || [];
                this.chartLinks = result.links || [];
                this.dataLoaded = true;
            }
        } catch (error) {
            throw error;
        } finally {
            this.isLoading = false;
            this.chartRendered = false;
            // Single render attempt with optimal timing
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.tryRenderChart();
            }, 150);
        }
    }

    async loadOpportunityData() {
        try {
            const result = await getOpportunityChartData({ opportunityId: this.recordId });

            if (result) {
                this.opportunityInfo = result.opportunityInfo;
                this.stakeholders    = result.nodes || [];
                this.cases           = result.cases || [];
                this.dataLoaded      = true;
            }
        } catch (error) {
            throw error;
        } finally {
            this.isLoading = false;
            this.chartRendered = false;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.tryRenderChart();
            }, 150);
        }
    }

    renderedCallback() {
        if (this.scriptsLoaded) {
            return; // Don't keep trying to render on every render
        }

        loadScript(this, D3)
            .then(() => loadScript(this, D3FLEXTREE))
            .then(() => loadScript(this, D3ORGCHART))
            .then(() => {
                this.scriptsLoaded = true;
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    this.tryRenderChart();
                }, 100);
            })
            .catch(error => {
                this.showError('Error loading chart library', error);
            });
    }

    tryRenderChart(retryCount = 0) {
        // Prevent concurrent renders
        if (this.isRendering || this.chartRendered) {
            return;
        }

        // Check prerequisites
        if (!this.scriptsLoaded || !this.dataLoaded || this.isLoading) {
            return;
        }

        const container = this.template.querySelector('.soc-chart-container');
        if (!container) {
            if (retryCount < 3) {
                setTimeout(() => {
                    this.tryRenderChart(retryCount + 1);
                }, 100);
            }
            return;
        }

        // Set rendering flag
        this.isRendering = true;

        const objType = this.effectiveObjectType;
        try {
            if (objType === 'Account') {
                this.renderAccountOrgChart(container);
            } else if (objType === 'Opportunity') {
                this.renderOpportunityOrgChart(container);
            }
            this.chartRendered = true;
        } catch (error) {
            this.showError('Error rendering chart', error);
        } finally {
            this.isRendering = false;
        }
    }

    // Event Handlers
    handleSearch(event) {
        this.searchTerm = event.target.value;
        this.rerenderChart();
    }

    handleRoleFilter(event) {
        this.selectedRole = event.detail.value;
        this.rerenderChart();
    }

    handleToggleOpportunities() {
        this.showOpportunities = !this.showOpportunities;
        this.rerenderChart();
    }

    handleToggleCases() {
        this.showCases = !this.showCases;
        this.rerenderChart();
    }

    rerenderChart() {
        // Don't re-render if currently rendering
        if (this.isRendering) {
            return;
        }

        this.chartRendered = false;
        this.isRendering = true;

        const container = this.template.querySelector('.soc-chart-container');
        if (container && this.scriptsLoaded && this.dataLoaded) {
            try {
                const objType = this.effectiveObjectType;
                if (objType === 'Account') {
                    this.renderAccountOrgChart(container);
                } else if (objType === 'Opportunity') {
                    this.renderOpportunityOrgChart(container);
                }
                this.chartRendered = true;
            } catch (error) {
                // Silent failure for re-rendering
            } finally {
                this.isRendering = false;
            }
        } else {
            this.isRendering = false;
        }
    }

    renderAccountOrgChart(container) {
        container.replaceChildren();

        const chartData = this.buildAccountHierarchy();

        if (chartData.length === 0) {
            const msg = document.createElement('div');
            msg.setAttribute('style', 'display:flex;align-items:center;justify-content:center;height:100%;color:#706e6b;');
            msg.textContent = 'No contacts found. Add contacts to the account.';
            container.appendChild(msg);
            return;
        }

        // Deep clone to avoid LWC proxy issues with d3 mutations
        const clonedData = JSON.parse(JSON.stringify(chartData));

        this.chart = new window.d3.OrgChart()
            .container(container)
            .data(clonedData)
            .nodeWidth((d) => this.getNodeWidth(d))
            .nodeHeight((d) => this.getNodeHeight(d))
            .childrenMargin(() => 80)
            .compactMarginBetween(() => 50)
            .siblingsMargin(() => 60)
            .neighbourMargin(() => 80)
            .buttonContent(({ node }) => this.getExpandButtonContent(node))
            .nodeContent((d) => this.getNodeTemplate(d))
            .render();

        this.chart.fit();
    }

    renderOpportunityOrgChart(container) {
        container.replaceChildren();

        const chartData = this.buildOpportunityHierarchy();

        if (chartData.length === 0) {
            const msg = document.createElement('div');
            msg.setAttribute('style', 'display:flex;align-items:center;justify-content:center;height:100%;color:#706e6b;');
            msg.textContent = 'No stakeholders found. Add contacts to this opportunity.';
            container.appendChild(msg);
            return;
        }

        // Deep clone to avoid LWC proxy issues with d3 mutations
        const clonedData = JSON.parse(JSON.stringify(chartData));

        this.chart = new window.d3.OrgChart()
            .container(container)
            .data(clonedData)
            .nodeWidth((d) => this.getNodeWidth(d))
            .nodeHeight((d) => this.getNodeHeight(d))
            .childrenMargin(() => 80)
            .compactMarginBetween(() => 50)
            .siblingsMargin(() => 60)
            .neighbourMargin(() => 80)
            .buttonContent(({ node }) => this.getExpandButtonContent(node))
            .nodeContent((d) => this.getNodeTemplate(d))
            .render();

        this.chart.fit();
    }

    getExpandButtonContent(node) {
        if (!node.children && !node._children) {
            return '';
        }
        const childCount = node.children ? node.children.length : (node._children ? node._children.length : 0);
        const isExpanded = !!node.children;
        const icon = isExpanded ? '−' : '+';
        return `
            <div style="display:flex;flex-direction:column;align-items:center;position:relative;margin-top:20px;">
                <div style="width:26px;height:26px;border-radius:50%;background:#0176d3;color:white;display:flex;align-items:center;justify-content:center;font-size:16px;font-weight:bold;cursor:pointer;box-shadow:0 2px 8px rgba(0,0,0,0.25);border:2px solid white;">
                    ${icon}
                </div>
                <div style="background:#0176d3;color:white;padding:1px 6px;border-radius:8px;font-size:9px;margin-top:3px;font-weight:600;">${childCount}</div>
            </div>
        `;
    }

    handleNodeClick(d) {
        // Toggle expand/collapse on click
        if (this.chart && d.data) {
            // Only toggle if the node has children
            if (d.children || d._children) {
                this.chart.toggleExpandNode(d);
            }
        }
    }

    getNodeWidth(d) {
        const type = d.data.nodeType;
        if (type === 'Root')        return 200;
        if (type === 'Account')     return 280;
        if (type === 'Opportunity') return 260;
        if (type === 'Case')        return 260;
        return 300;
    }

    getNodeHeight(d) {
        const type = d.data.nodeType;
        if (type === 'Root')        return 55;
        if (type === 'Account')     return 100;
        if (type === 'Opportunity') return 95;
        if (type === 'Case')        return 95;
        return 180;
    }

    buildAccountHierarchy() {
        const data = [];

        if (this.accountInfo) {
            data.push({
                id: this.accountInfo.id || this.recordId,
                parentId: '',
                name: this.accountInfo.name || 'Account',
                nodeType: 'Account',
                industry: this.accountInfo.industry || ''
            });

            const accountId = this.accountInfo.id || this.recordId;

            // Add Opportunities if toggled on
            if (this.showOpportunities) {
                this.opportunities.forEach(opp => {
                    data.push({
                        id: opp.id,
                        parentId: accountId,
                        name: opp.name || 'Opportunity',
                        nodeType: 'Opportunity',
                        stageName: opp.stageName || '',
                        amount: opp.amount
                    });
                });
            }

            // Add Cases if toggled on
            if (this.showCases) {
                this.cases.forEach(caseItem => {
                    data.push({
                        id: caseItem.id,
                        parentId: accountId,
                        name: caseItem.caseNumber || 'Case',
                        nodeType: 'Case',
                        subject: caseItem.subject || '',
                        status: caseItem.status || '',
                        isClosed: caseItem.isClosed
                    });
                });
            }

            // Build contact-opportunity map
            const contactOppMap = new Map();
            this.chartLinks.forEach(link => {
                if (link.linkType === 'contact-opportunity') {
                    contactOppMap.set(link.sourceId, link.targetId);
                }
            });

            // Get filtered stakeholders
            const contactIds = new Set(this.filteredStakeholders.map(c => c.id));

            this.filteredStakeholders.forEach(contact => {
                let parentId;

                // Priority 1: Reports to relationship
                if (contact.reportsToId && contactIds.has(contact.reportsToId)) {
                    parentId = contact.reportsToId;
                }
                // Priority 2: Link to opportunity if showing opportunities
                else if (this.showOpportunities && contactOppMap.has(contact.id)) {
                    parentId = contactOppMap.get(contact.id);
                }
                // Priority 3: Default to account
                else {
                    parentId = accountId;
                }

                data.push({
                    id: contact.id,
                    parentId: parentId,
                    name: contact.name || 'Contact',
                    nodeType: 'Contact',
                    title: contact.title || '',
                    role: contact.role || '',
                    email: contact.email || '',
                    phone: contact.phone || '',
                    photoUrl: contact.photoUrl || null,
                    isPrimary: contact.isPrimary,
                    strength: contact.relationshipStrength || 3
                });
            });
        }

        return data;
    }

    buildOpportunityHierarchy() {
        const data = [];
        const stakeholderIds = new Set(this.filteredStakeholders.map(s => s.id));

        // Determine root: Opportunity node (when toggled ON) or virtual "Stakeholders" root
        let rootId;
        if (this.showOpportunities && this.opportunityInfo) {
            rootId = this.opportunityInfo.id;
            data.push({
                id: rootId,
                parentId: '',
                name: this.opportunityInfo.name || 'Opportunity',
                nodeType: 'Opportunity',
                stageName: this.opportunityInfo.stageName || '',
                amount: this.opportunityInfo.amount
            });
        } else {
            rootId = 'opportunity-root';
            data.push({ id: rootId, parentId: '', name: 'Stakeholders', nodeType: 'Root' });
        }

        // Build a set of contact IDs that will actually appear (for cases parentId)
        const contactNodeIds = new Set();

        this.filteredStakeholders.forEach(contact => {
            let parentId;
            if (contact.reportsToId && stakeholderIds.has(contact.reportsToId)) {
                parentId = contact.reportsToId;
            } else {
                parentId = rootId;
            }

            contactNodeIds.add(contact.id);
            data.push({
                id: contact.id,
                parentId: parentId,
                name: contact.name || 'Contact',
                nodeType: 'Contact',
                title: contact.title || '',
                role: contact.role || '',
                email: contact.email || '',
                phone: contact.phone || '',
                photoUrl: contact.photoUrl || null,
                isPrimary: contact.isPrimary,
                strength: contact.relationshipStrength || 3
            });
        });

        // Cases as children of their linked contact (when toggled ON)
        if (this.showCases && this.cases && this.cases.length > 0) {
            this.cases.forEach(c => {
                if (c.contactId && contactNodeIds.has(c.contactId)) {
                    data.push({
                        id: c.id,
                        parentId: c.contactId,
                        name: c.caseNumber || 'Case',
                        nodeType: 'Case',
                        subject: c.subject || '',
                        status: c.status || '',
                        isClosed: c.isClosed
                    });
                }
            });
        }

        return data;
    }

    getNodeTemplate(d) {
        const data = d.data;

        if (data.nodeType === 'Account') {
            return `
                <div style="width:280px;background:linear-gradient(135deg,#1e3a5f 0%,#1e40af 100%);border-radius:12px;padding:20px;color:white;box-shadow:0 6px 20px rgba(0,0,0,0.2);cursor:pointer;">
                    <div style="display:flex;align-items:center;gap:14px;">
                        <div style="width:56px;height:56px;background:rgba(255,255,255,0.15);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:28px;">🏢</div>
                        <div style="flex:1;min-width:0;">
                            <div style="font-size:10px;text-transform:uppercase;letter-spacing:1px;opacity:0.7;margin-bottom:4px;">Account</div>
                            <div style="font-size:16px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${this.escapeHtml(this.truncateText(data.name, 22))}</div>
                            ${data.industry ? `<div style="font-size:12px;opacity:0.85;margin-top:4px;display:flex;align-items:center;gap:6px;"><span>🏭</span>${this.escapeHtml(data.industry)}</div>` : ''}
                        </div>
                    </div>
                </div>
            `;
        }

        if (data.nodeType === 'Opportunity') {
            return `
                <div style="width:260px;background:linear-gradient(135deg,#7c3aed 0%,#a855f7 100%);border-radius:12px;padding:18px;color:white;box-shadow:0 6px 20px rgba(124,58,237,0.3);cursor:pointer;">
                    <div style="display:flex;align-items:center;gap:12px;">
                        <div style="width:50px;height:50px;background:rgba(255,255,255,0.15);border-radius:10px;display:flex;align-items:center;justify-content:center;font-size:24px;">💰</div>
                        <div style="flex:1;min-width:0;">
                            <div style="font-size:10px;text-transform:uppercase;letter-spacing:1px;opacity:0.7;margin-bottom:4px;">Opportunity</div>
                            <div style="font-size:14px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${this.escapeHtml(this.truncateText(data.name, 20))}</div>
                            <div style="display:flex;align-items:center;gap:8px;margin-top:6px;">
                                <span style="background:rgba(255,255,255,0.2);padding:3px 8px;border-radius:6px;font-size:10px;">${this.escapeHtml(data.stageName || 'Stage')}</span>
                                ${data.amount ? `<span style="font-size:14px;font-weight:700;">${this.escapeHtml(this.formatCurrency(data.amount))}</span>` : ''}
                            </div>
                        </div>
                    </div>
                </div>
            `;
        }

        if (data.nodeType === 'Case') {
            const bgColor = data.isClosed ? 'linear-gradient(135deg,#4b5563 0%,#6b7280 100%)' : 'linear-gradient(135deg,#16a34a 0%,#22c55e 100%)';
            const statusIcon = data.isClosed ? '✅' : '🔄';
            const statusText = data.isClosed ? 'Closed' : 'Open';
            return `
                <div style="width:260px;background:${this.escapeHtml(bgColor)};border-radius:12px;padding:18px;color:white;box-shadow:0 6px 20px rgba(0,0,0,0.15);cursor:pointer;">
                    <div style="display:flex;align-items:center;gap:12px;">
                        <div style="width:50px;height:50px;background:rgba(255,255,255,0.15);border-radius:10px;display:flex;align-items:center;justify-content:center;font-size:24px;">📋</div>
                        <div style="flex:1;min-width:0;">
                            <div style="font-size:10px;text-transform:uppercase;letter-spacing:1px;opacity:0.7;margin-bottom:4px;">Case</div>
                            <div style="font-size:14px;font-weight:700;">${this.escapeHtml(data.name)}</div>
                            <div style="font-size:11px;opacity:0.9;margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${this.escapeHtml(this.truncateText(data.subject || '', 25))}</div>
                            <div style="display:flex;align-items:center;gap:6px;margin-top:8px;">
                                <span style="background:rgba(255,255,255,0.2);padding:3px 10px;border-radius:6px;font-size:10px;display:flex;align-items:center;gap:4px;">${statusIcon} ${this.escapeHtml(statusText)}</span>
                            </div>
                        </div>
                    </div>
                </div>
            `;
        }

        return this.getContactNodeTemplate(d);
    }

    getContactNodeTemplate(d) {
        const data = d.data;

        if (data.nodeType === 'Root') {
            return `
                <div style="background:#f3f3f3;border-radius:10px;padding:12px 20px;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.1);">
                    <div style="font-size:13px;font-weight:600;color:#706e6b;">${this.escapeHtml(data.name)}</div>
                </div>
            `;
        }

        const initials = this.getInitials(data.name);
        const sentimentColor = this.getSentimentColor(data.role);
        const sentimentBadge = this.getSentimentBadge(data.role);
        const strengthBadge = this.getStrengthBadge(data.strength);
        const primaryBadge = data.isPrimary ? '<span style="background:#0176d3;color:white;padding:3px 8px;border-radius:4px;font-size:10px;font-weight:600;">PRIMARY</span>' : '';
        const roleBadge = data.role ? this.getRoleBadge(data.role) : '';

        // Contact info section
        const emailSection = data.email ? `
            <div style="display:flex;align-items:center;gap:6px;margin-top:6px;">
                <span style="font-size:12px;">📧</span>
                <span style="font-size:11px;color:#0176d3;text-decoration:none;">${this.escapeHtml(this.truncateText(data.email, 25))}</span>
            </div>
        ` : '';

        const phoneSection = data.phone ? `
            <div style="display:flex;align-items:center;gap:6px;margin-top:4px;">
                <span style="font-size:12px;">📱</span>
                <span style="font-size:11px;color:#181818;">${this.escapeHtml(data.phone)}</span>
            </div>
        ` : '';

        // Avatar section - use photo if available, otherwise show initials
        const avatarHtml = data.photoUrl ?
            `<img src="${this.escapeHtml(data.photoUrl)}" alt="${this.escapeHtml(data.name)}" style="width:56px;height:56px;border-radius:50%;object-fit:cover;flex-shrink:0;box-shadow:0 2px 8px rgba(1,118,211,0.3);border:2px solid white;" />` :
            `<div style="width:56px;height:56px;border-radius:50%;background:linear-gradient(135deg,#0176d3 0%,#1b96ff 100%);display:flex;align-items:center;justify-content:center;color:white;font-size:18px;font-weight:700;flex-shrink:0;box-shadow:0 2px 8px rgba(1,118,211,0.3);">${this.escapeHtml(initials)}</div>`;

        return `
            <div style="width:300px;background:#ffffff;border-radius:12px;box-shadow:0 4px 16px rgba(0,0,0,0.12);overflow:hidden;cursor:pointer;border-top:4px solid ${this.escapeHtml(sentimentColor)};">
                <!-- Header with avatar and name -->
                <div style="display:flex;padding:16px;gap:14px;align-items:flex-start;background:linear-gradient(180deg,#fafbfc 0%,#ffffff 100%);">
                    ${avatarHtml}
                    <div style="flex:1;min-width:0;">
                        <div style="font-size:15px;font-weight:700;color:#181818;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${this.escapeHtml(data.name)}</div>
                        <div style="font-size:12px;color:#706e6b;margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${this.escapeHtml(data.title || 'No Title')}</div>
                        ${roleBadge}
                    </div>
                </div>
                <!-- Contact Info -->
                <div style="padding:0 16px 12px 16px;">
                    ${emailSection}
                    ${phoneSection}
                </div>
                <!-- Badges section -->
                <div style="padding:12px 16px;background:#f8fafc;border-top:1px solid #e5e7eb;display:flex;flex-wrap:wrap;gap:8px;align-items:center;">
                    ${sentimentBadge}
                    ${strengthBadge}
                    ${primaryBadge}
                </div>
            </div>
        `;
    }

    getRoleBadge(role) {
        const roleColors = {
            'Champion': { bg: '#cdefc4', color: '#2e844a', icon: '⭐' },
            'Decision Maker': { bg: '#e5f2fd', color: '#0176d3', icon: '👑' },
            'Economic Buyer': { bg: '#f3e8ff', color: '#7c3aed', icon: '💰' },
            'Technical Buyer': { bg: '#e5f2fd', color: '#0176d3', icon: '🔧' },
            'Influencer': { bg: '#fef3c7', color: '#d97706', icon: '📢' },
            'Blocker': { bg: '#feded8', color: '#ba0517', icon: '🚫' },
            'User': { bg: '#f3f3f3', color: '#706e6b', icon: '👤' },
            'Executive Sponsor': { bg: '#cdefc4', color: '#2e844a', icon: '🎯' },
            'Gatekeeper': { bg: '#ffddca', color: '#fe5c02', icon: '🚪' }
        };

        const config = roleColors[role] || { bg: '#f3f3f3', color: '#706e6b', icon: '👤' };
        return `<div style="display:inline-flex;align-items:center;gap:4px;margin-top:6px;padding:4px 10px;background:${this.escapeHtml(config.bg)};border-radius:12px;">
            <span style="font-size:12px;">${config.icon}</span>
            <span style="font-size:11px;font-weight:600;color:${this.escapeHtml(config.color)};">${this.escapeHtml(role)}</span>
        </div>`;
    }

    getSentimentColor(role) {
        if (!role) return '#747474';
        const champions = ['Champion', 'Economic Buyer', 'Executive Sponsor'];
        const detractors = ['Detractor', 'Blocker'];
        if (champions.includes(role)) return '#2e844a';
        if (detractors.includes(role)) return '#ba0517';
        return '#747474';
    }

    getInitials(name) {
        if (!name) return '?';
        const parts = name.split(' ');
        if (parts.length >= 2) {
            return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
        }
        return name.substring(0, 2).toUpperCase();
    }

    getSentimentBadge(role) {
        const baseStyle = 'padding:2px 6px;border-radius:4px;font-size:9px;font-weight:500;';

        if (!role) return `<span style="${baseStyle}background:#f3f3f3;color:#747474;">Neutral</span>`;

        const champions = ['Champion', 'Economic Buyer', 'Executive Sponsor'];
        const detractors = ['Detractor', 'Blocker'];

        if (champions.includes(role)) {
            return `<span style="${baseStyle}background:#cdefc4;color:#2e844a;">Positive</span>`;
        }
        if (detractors.includes(role)) {
            return `<span style="${baseStyle}background:#feded8;color:#ba0517;">Detractor</span>`;
        }
        return `<span style="${baseStyle}background:#f3f3f3;color:#747474;">Neutral</span>`;
    }

    getStrengthBadge(strength) {
        const baseStyle = 'padding:2px 6px;border-radius:4px;font-size:9px;font-weight:500;';
        const strengthVal = strength || 3;

        if (strengthVal >= 4) {
            return `<span style="${baseStyle}background:#cdefc4;color:#2e844a;">Strong</span>`;
        }
        if (strengthVal === 3) {
            return `<span style="${baseStyle}background:#ffddca;color:#fe5c02;">Medium</span>`;
        }
        return `<span style="${baseStyle}background:#feded8;color:#ba0517;">Weak</span>`;
    }

    truncateText(text, maxLength) {
        if (!text) return '';
        if (text.length <= maxLength) return text;
        return text.substring(0, maxLength) + '...';
    }

    formatCurrency(amount) {
        if (!amount) return '';
        if (amount >= 1000000) return '$' + (amount / 1000000).toFixed(1) + 'M';
        if (amount >= 1000) return '$' + (amount / 1000).toFixed(0) + 'K';
        return '$' + amount.toFixed(0);
    }

    escapeHtml(text) {
        if (!text) return '';
        return String(text)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    // Chart controls
    handleExpandAll() {
        if (this.chart) {
            this.chart.expandAll();
        }
    }

    handleCollapseAll() {
        if (this.chart) {
            this.chart.collapseAll();
        }
    }

    async handleRefresh() {
        this.dataFetched = false;
        this.isLoading = true;
        try {
            await this.loadData();
            this.showToast('Success', 'Relationship map refreshed', 'success');
        } catch (error) {
            this.showToast('Error', 'Failed to refresh data', 'error');
        }
    }

    handleZoomIn() {
        if (this.chart) {
            this.chart.zoomIn();
        }
    }

    handleZoomOut() {
        if (this.chart) {
            this.chart.zoomOut();
        }
    }

    handleZoomReset() {
        if (this.chart) {
            this.chart.fit();
        }
    }

    showError(title, error) {
        const message = error?.body?.message || error?.message || 'Unknown error';
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant: 'error'
        }));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
}