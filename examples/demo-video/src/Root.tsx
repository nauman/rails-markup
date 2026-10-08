import {Composition, Folder, Series} from 'remotion';
import {Opening} from './Opening';
import {Comment} from './Comment';
import {Attachment} from './Attachment';
import {Review} from './Review';
import {Acknowledged} from './Acknowledged';
import {Closing} from './Closing';
import {Board} from './Board';
export const Walkthrough = () => <Series>
 <Series.Sequence name="Opening" durationInFrames={120}><Opening /></Series.Sequence>
 <Series.Sequence name="Comment" durationInFrames={180}><Comment /></Series.Sequence>
 <Series.Sequence name="Attachment" durationInFrames={180}><Attachment /></Series.Sequence>
 <Series.Sequence name="Review" durationInFrames={210}><Review /></Series.Sequence>
 <Series.Sequence name="Acknowledged" durationInFrames={150}><Acknowledged /></Series.Sequence>
 <Series.Sequence name="Board" durationInFrames={180}><Board /></Series.Sequence>
 <Series.Sequence name="Closing" durationInFrames={120}><Closing /></Series.Sequence>
</Series>;
export const RemotionRoot = () => <>
 <Composition id="RailsMarkupDemo" component={Walkthrough} width={1920} height={1080} fps={30} durationInFrames={1140} />
 <Folder name="Scenes">
 <Composition id="Opening" component={Opening} width={1920} height={1080} fps={30} durationInFrames={120} />
 <Composition id="Comment" component={Comment} width={1920} height={1080} fps={30} durationInFrames={180} />
 <Composition id="Attachment" component={Attachment} width={1920} height={1080} fps={30} durationInFrames={180} />
 <Composition id="Review" component={Review} width={1920} height={1080} fps={30} durationInFrames={210} />
 <Composition id="Acknowledged" component={Acknowledged} width={1920} height={1080} fps={30} durationInFrames={150} />
 <Composition id="Board" component={Board} width={1920} height={1080} fps={30} durationInFrames={180} />
 <Composition id="Closing" component={Closing} width={1920} height={1080} fps={30} durationInFrames={120} />
</Folder>
</>;
