// Shared by the person card and its friends list.

const PALETTE = [
    { primary: '#1D9E75', fill: 'rgba(29, 158, 117, 0.12)' },
    { primary: '#2563EB', fill: 'rgba(37, 99, 235, 0.10)' },
    { primary: '#8B5CF6', fill: 'rgba(139, 92, 246, 0.10)' },
    { primary: '#F97316', fill: 'rgba(249, 115, 22, 0.12)' },
    { primary: '#E94560', fill: 'rgba(233, 69, 96, 0.10)' }
];

function hashProgram(name) {
    if (!name) return 0;
    let h = 0;
    for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) | 0;
    return Math.abs(h) % PALETTE.length;
}

export function programColors(name) {
    return PALETTE[hashProgram(name)];
}

export function programPillStyle(program) {
    const c = programColors(program);
    return `background:${c.fill};color:${c.primary};`;
}

export function computeInitials(name) {
    if (!name) return '?';
    const trimmed = String(name).trim();
    if (!trimmed) return '?';
    const parts = trimmed.split(/\s+/);
    if (parts.length >= 2) {
        return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return trimmed.substring(0, 2).toUpperCase();
}

export function formatShortDate(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const yy = String(d.getFullYear()).slice(-2);
    return `${mm}/${dd}/${yy}`;
}

// The arguments getFriendDetails takes for some friend references: plain lists
// of strings, because an LWC cannot pass a list of Apex objects.
export function detailsArgs(refs) {
    return {
        personIds: (refs || []).map((r) => r.personId),
        programs: (refs || []).map((r) => r.program || '')
    };
}

// Puts each reference's reward back on the friend loaded for it. The rewards
// are already known to the card, so the server doesn't send them again.
export function attachRewards(friends, refs) {
    const rewardById = new Map((refs || []).map((r) => [r.personId, r.reward]));
    return (friends || []).map((f) => ({
        ...f,
        reward: rewardById.get(f.personId) || null
    }));
}

// What a friend row shows, from a friend as the server sends it.
export function decorateFriend(f) {
    const earned =
        f.reward &&
        (f.reward.state === 'PAID' ||
            f.reward.state === 'EARNED' ||
            f.reward.state === 'SENT');
    const rewardDateStr = earned ? formatShortDate(f.reward.dateEarned) : null;
    const statusText = earned
        ? rewardDateStr
            ? `Reward earned ${rewardDateStr}`
            : 'Reward earned'
        : '';
    const displayName = f.displayName || f.email || 'Anonymous';
    const milestones = (f.steps || []).map((s) => ({
        key: s.name,
        label: s.label,
        date: s.dateCompleted ? formatShortDate(s.dateCompleted) : null,
        rowClass: s.dateCompleted
            ? 'milestone-row milestone-row-completed'
            : 'milestone-row milestone-row-pending'
    }));
    return {
        key: f.personId,
        program: f.program || 'unknown',
        displayName,
        sfdcUrl: f.sfdcRecordId
            ? `/lightning/r/${f.sfdcObjectType}/${f.sfdcRecordId}/view`
            : null,
        isLinked: !!f.sfdcRecordId,
        avatarInitials: computeInitials(displayName),
        avatarClass: earned ? 'avatar avatar-success' : 'avatar avatar-neutral',
        avatarIsEarned: earned,
        statusText,
        rewardStateText: earned ? f.reward.amountLabel : 'no reward yet',
        rewardStateClass: earned ? 'reward-amount-earned' : 'reward-pending',
        milestones,
        hasMilestones: milestones.length > 0
    };
}

// Friends grouped by program, in the order each program first appears.
export function groupByProgram(friends) {
    const byProgram = new Map();
    for (const f of friends) {
        const d = decorateFriend(f);
        if (!byProgram.has(d.program)) byProgram.set(d.program, []);
        byProgram.get(d.program).push(d);
    }
    return [...byProgram.entries()].map(([program, list]) => ({
        program,
        programStyle: programPillStyle(program),
        friends: list
    }));
}
