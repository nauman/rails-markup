import {AbsoluteFill, CanvasImage, Series, staticFile} from 'remotion';

const DrawingStep = ({number, title, caption, image}: {number: string; title: string; caption: string; image: string}) => <AbsoluteFill style={{background: '#f6f6f4', color: '#15161a', fontFamily: 'Arial, sans-serif', alignItems: 'center'}}>
  <div style={{marginTop: 28, fontSize: 17, letterSpacing: 3, color: '#3a5a3f'}}>RAILS MARKUP · {number} / 05</div>
  <h1 style={{fontSize: 44, margin: '16px 0 10px', letterSpacing: -1}}>{title}</h1>
  <div style={{fontSize: 23, color: '#58616c', textAlign: 'center'}}>{caption}</div>
  <div style={{position: 'absolute', top: 191, width: 720, height: 620, display: 'flex', justifyContent: 'center', alignItems: 'center'}}>
    <CanvasImage src={staticFile(`drawing/${image}.png`)} style={{maxWidth: '100%', maxHeight: '100%', objectFit: 'contain', borderRadius: 12, boxShadow: '0 12px 36px #15161a18'}} />
  </div>
  <div style={{position: 'absolute', bottom: 32, fontSize: 18, color: '#3a5a3f'}}>nauman.github.io/rails-markup · nauman.one / Pavelabs</div>
</AbsoluteFill>;

// Screenshot sequence captured from the real toolbar and persisted dashboard.
export const DrawingDemo = () => <Series>
  <Series.Sequence durationInFrames={90}><DrawingStep number="01" title="Attach the screenshot." caption="Capture a tab, upload an image, or paste one." image="attached" /></Series.Sequence>
  <Series.Sequence durationInFrames={90}><DrawingStep number="02" title="Box the exact detail." caption="Make the feedback specific." image="boxed" /></Series.Sequence>
  <Series.Sequence durationInFrames={90}><DrawingStep number="03" title="Point to the problem." caption="Add an arrow directly on the image." image="arrow" /></Series.Sequence>
  <Series.Sequence durationInFrames={120}><DrawingStep number="04" title="Highlight. Add the context." caption="The image and comment travel together." image="drawn" /></Series.Sequence>
  <Series.Sequence durationInFrames={150}><DrawingStep number="05" title="Review it in the dashboard." caption="The saved drawing stays with the feedback." image="saved" /></Series.Sequence>
</Series>;
