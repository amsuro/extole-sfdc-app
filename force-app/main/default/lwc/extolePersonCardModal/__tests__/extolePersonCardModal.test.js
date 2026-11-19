/* eslint-disable @lwc/lwc/no-async-operation, no-await-in-loop */
import { createElement } from 'lwc';
import ExtolePersonCardModal from 'c/extolePersonCardModal';
import getFriendDetails from '@salesforce/apex/ExtolePersonCardController.getFriendDetails';

jest.mock(
    'lightning/modal',
    () => {
        const { LightningElement } = require('lwc');
        return { __esModule: true, default: class extends LightningElement {} };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/ExtolePersonCardController.getFriendDetails',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const ref = (i) => ({ personId: `p${i}`, program: 'refer-a-friend' });
const friend = (i) => ({
    personId: `p${i}`,
    program: 'refer-a-friend',
    displayName: `Friend ${i}`
});
const refs = (n) => Array.from({ length: n }, (_, i) => ref(i));

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
async function settle() {
    for (let i = 0; i < 5; i++) await flush();
}

function mount(friendRefs, loaded = []) {
    const el = createElement('c-extole-person-card-modal', {
        is: ExtolePersonCardModal
    });
    el.friendRefs = friendRefs;
    el.loaded = loaded;
    document.body.appendChild(el);
    return el;
}

const names = (el) =>
    [...el.shadowRoot.querySelectorAll('c-extole-friend-card')].map(
        (c) => c.friend.displayName
    );
const buttons = (el) => [...el.shadowRoot.querySelectorAll('lightning-button')];

beforeEach(() => {
    getFriendDetails.mockReset();
    getFriendDetails.mockImplementation(({ personIds }) =>
        Promise.resolve(personIds.map((id) => friend(Number(id.slice(1)))))
    );
});

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
});

describe('extolePersonCardModal', () => {
    it('shows ten to a page and loads only what it shows', async () => {
        const el = mount(refs(95));
        await settle();

        expect(names(el)).toHaveLength(10);
        expect(names(el)[0]).toBe('Friend 0');
        expect(getFriendDetails).toHaveBeenCalledTimes(1);
        // Plain lists of strings: an LWC cannot pass a list of Apex objects.
        expect(getFriendDetails.mock.calls[0][0].personIds).toHaveLength(10);
        expect(getFriendDetails.mock.calls[0][0].programs).toHaveLength(10);
        expect(el.shadowRoot.querySelector('.pager-range').textContent).toBe(
            '1–10 of 95'
        );
    });

    it('does not look up friends the card already loaded', async () => {
        const loaded = Array.from({ length: 10 }, (_, i) => friend(i));
        const el = mount(refs(30), loaded);
        await settle();

        expect(names(el)).toHaveLength(10);
        expect(getFriendDetails).not.toHaveBeenCalled();
    });

    it('moves between pages and reaches the last short page', async () => {
        const el = mount(refs(25));
        await settle();
        const [prev, next] = buttons(el);
        expect(prev.disabled).toBe(true);

        next.click();
        await settle();
        next.click();
        await settle();

        expect(names(el)).toHaveLength(5);
        expect(names(el)[0]).toBe('Friend 20');
        expect(el.shadowRoot.querySelector('.pager-range').textContent).toBe(
            '21–25 of 25'
        );
        expect(buttons(el)[1].disabled).toBe(true);
    });

    it('asks again when a call only returns some of the page', async () => {
        getFriendDetails
            .mockImplementationOnce(({ personIds }) =>
                Promise.resolve(
                    personIds
                        .slice(0, 4)
                        .map((id) => friend(Number(id.slice(1))))
                )
            )
            .mockImplementation(({ personIds }) =>
                Promise.resolve(
                    personIds.map((id) => friend(Number(id.slice(1))))
                )
            );
        const el = mount(refs(10));
        await settle();

        expect(getFriendDetails).toHaveBeenCalledTimes(2);
        expect(getFriendDetails.mock.calls[1][0].personIds).toHaveLength(6);
        expect(names(el)).toHaveLength(10);
    });

    it('says so when nothing comes back, instead of looping', async () => {
        getFriendDetails.mockResolvedValue([]);
        const el = mount(refs(10));
        await settle();

        expect(getFriendDetails).toHaveBeenCalledTimes(1);
        expect(el.shadowRoot.querySelector('.error-banner')).not.toBeNull();
    });
});
