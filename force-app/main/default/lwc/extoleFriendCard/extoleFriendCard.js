import { LightningElement, api } from 'lwc';

// One friend: who they are, their reward, and how far they got.
export default class ExtoleFriendCard extends LightningElement {
    @api friend;
}
