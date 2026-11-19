import {
    programColors,
    computeInitials,
    formatShortDate,
    decorateFriend,
    groupByProgram,
    detailsArgs,
    attachRewards
} from 'c/extolePersonCardUtils';

describe('helpers', () => {
    it('colors are stable per program and always defined', () => {
        for (const name of ['', null, 'a', 'refer-a-friend', 'x'.repeat(500)]) {
            expect(programColors(name)).toBeDefined();
            expect(programColors(name)).toBe(programColors(name));
        }
    });

    it('initials handle odd names', () => {
        expect(computeInitials('')).toBe('?');
        expect(computeInitials('   ')).toBe('?');
        expect(computeInitials('Maria Alvarez')).toBe('MA');
        expect(computeInitials('Cher')).toBe('CH');
    });

    it('dates are short, and bad ones are blank', () => {
        expect(formatShortDate('2026-11-18T08:00:00')).toBe('11/18/26');
        expect(formatShortDate('nope')).toBe('');
        expect(formatShortDate(null)).toBe('');
    });
});

describe('decorateFriend', () => {
    it('shows an earned reward with its amount and date', () => {
        const d = decorateFriend({
            personId: 'p1',
            displayName: 'Maria Alvarez',
            program: 'refer-a-friend',
            reward: {
                state: 'EARNED',
                amountLabel: '$50',
                dateEarned: '2026-11-18T08:00:00'
            },
            steps: [
                { name: 'a', label: 'Signed Up', dateCompleted: '2026-10-21' }
            ]
        });
        expect(d.rewardStateText).toBe('$50');
        expect(d.statusText).toBe('Reward earned 11/18/26');
        expect(d.avatarIsEarned).toBe(true);
        expect(d.milestones[0].rowClass).toContain('completed');
    });

    it('shows no reward yet when there is none', () => {
        const d = decorateFriend({ personId: 'p1', email: 'a@example.com' });
        expect(d.rewardStateText).toBe('no reward yet');
        expect(d.displayName).toBe('a@example.com');
        expect(d.program).toBe('unknown');
        expect(d.hasMilestones).toBe(false);
    });

    it('says nothing about a reward it cannot rule out', () => {
        const friend = { personId: 'p1', program: 'x', reward: null };

        expect(decorateFriend(friend, true).rewardStateText).toBe('');
        expect(decorateFriend(friend, false).rewardStateText).toBe(
            'no reward yet'
        );
    });

    it('links to the Salesforce record when there is one', () => {
        const d = decorateFriend({
            personId: 'p1',
            sfdcRecordId: '003x',
            sfdcObjectType: 'Contact'
        });
        expect(d.sfdcUrl).toBe('/lightning/r/Contact/003x/view');
        expect(d.isLinked).toBe(true);
    });
});

describe('groupByProgram', () => {
    it('groups friends under their program in first-seen order', () => {
        const groups = groupByProgram([
            { personId: 'a', program: 'one' },
            { personId: 'b', program: 'two' },
            { personId: 'c', program: 'one' }
        ]);
        expect(groups.map((g) => g.program)).toEqual(['one', 'two']);
        expect(groups[0].friends.map((f) => f.key)).toEqual(['a', 'c']);
    });
});

describe('detailsArgs', () => {
    it('turns references into two plain lists that line up', () => {
        expect(
            detailsArgs([
                {
                    personId: 'p1',
                    program: 'one',
                    reward: { amountLabel: '$5' }
                },
                { personId: 'p2' }
            ])
        ).toEqual({ personIds: ['p1', 'p2'], programs: ['one', ''] });
        expect(detailsArgs(undefined)).toEqual({ personIds: [], programs: [] });
    });
});

describe('attachRewards', () => {
    it('puts each reference reward back on its friend', () => {
        const refs = [
            { personId: 'p1', reward: { amountLabel: '$5' } },
            { personId: 'p2', reward: null }
        ];
        const out = attachRewards(
            [{ personId: 'p1' }, { personId: 'p2' }, { personId: 'p3' }],
            refs
        );
        expect(out[0].reward).toEqual({ amountLabel: '$5' });
        expect(out[1].reward).toBeNull();
        expect(out[2].reward).toBeNull();
    });
});
