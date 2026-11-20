import LightningModal from 'lightning/modal';
import { api } from 'lwc';
import getFriendDetails from '@salesforce/apex/ExtolePersonCardController.getFriendDetails';
import {
    groupByProgram,
    detailsArgs,
    attachRewards
} from 'c/extolePersonCardUtils';

const PAGE_SIZE = 10;

export default class ExtolePersonCardModal extends LightningModal {
    @api friendRefs = [];
    @api loaded = [];
    @api friendsTruncated = false;
    @api rewardsTruncated = false;

    byId = {};
    page = 0;
    isLoading = false;
    error = null;

    connectedCallback() {
        const byId = {};
        for (const f of this.loaded || []) byId[f.personId] = f;
        this.byId = byId;
        this.ensurePageLoaded();
    }

    get total() {
        return (this.friendRefs || []).length;
    }

    get totalText() {
        return this.friendsTruncated ? `${this.total}+` : `${this.total}`;
    }

    get pageRefs() {
        const start = this.page * PAGE_SIZE;
        return (this.friendRefs || []).slice(start, start + PAGE_SIZE);
    }

    get groups() {
        return groupByProgram(
            this.pageRefs.map((r) => this.byId[r.personId]).filter(Boolean),
            this.rewardsTruncated
        );
    }

    get headerLabel() {
        return `Friends (${this.totalText})`;
    }

    get rangeText() {
        const start = this.page * PAGE_SIZE + 1;
        const end = Math.min(start + PAGE_SIZE - 1, this.total);
        return `${start}–${end} of ${this.totalText}`;
    }

    get hasPrev() {
        return this.page > 0;
    }

    get hasNext() {
        return (this.page + 1) * PAGE_SIZE < this.total;
    }

    get prevDisabled() {
        return !this.hasPrev || this.isLoading;
    }

    get nextDisabled() {
        return !this.hasNext || this.isLoading;
    }

    handlePrev() {
        this.page -= 1;
        this.ensurePageLoaded();
    }

    handleNext() {
        this.page += 1;
        this.ensurePageLoaded();
    }

    async ensurePageLoaded() {
        this.error = null;
        const missing = () =>
            this.pageRefs.filter((r) => !this.byId[r.personId]);
        if (missing().length === 0) return;
        this.isLoading = true;
        try {
            while (missing().length > 0) {
                // Each call has to finish before the next, because it only
                // returns what fits under the callout limit.
                const asked = missing();
                // eslint-disable-next-line no-await-in-loop
                const got = await getFriendDetails(detailsArgs(asked));
                if (!got || got.length === 0) {
                    this.error = 'Could not load every friend on this page.';
                    break;
                }
                const byId = { ...this.byId };
                for (const f of attachRewards(got, asked)) byId[f.personId] = f;
                this.byId = byId;
            }
        } catch (e) {
            this.error =
                (e && e.body && e.body.message) || 'Could not load friends.';
        } finally {
            this.isLoading = false;
        }
    }
}
