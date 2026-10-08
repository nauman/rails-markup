import {AbsoluteFill, CanvasImage, interpolate, staticFile, useCurrentFrame} from 'remotion';
type Props = {step: string; title: string; caption: string; image: string; top?: number; fit?: boolean};
export const Shot = ({step, title, caption, image, top = 0, fit = false}: Props) => {
 const frame = useCurrentFrame();
 const enter = interpolate(frame,[0,16],[0,1],{extrapolateRight:'clamp'});
 return <AbsoluteFill style={{background:'#0a0d13',color:'#e8edf2',fontFamily:'Arial, sans-serif'}}>
 <div style={{position:'absolute',left:100,top:62,color:'#34e5c4',fontSize:22,letterSpacing:4}}>RAILS MARKUP / {step}</div>
 <div style={{position:'absolute',left:100,top:104,fontSize:84,fontWeight:700,letterSpacing:-3,opacity:enter,transform:`translateY(${(1-enter)*12}px)`}}>{title}</div>
 <div style={{position:'absolute',left:104,top:202,fontSize:44,color:'#aebdca'}}>{caption}</div>
 <div style={{position:'absolute',left:100,top:286,width:1720,height:696,overflow:'hidden',border:'1px solid #28333f',borderRadius:18,background:'#0a0d13',opacity:enter}}>
 <CanvasImage src={staticFile(`captures/${image}.jpg`)} style={fit ? {width:'100%',height:'100%',objectFit:'contain'} : {position:'absolute',width:1500,height:937.5,left:110,top}} />
 </div>
 <div style={{position:'absolute',left:104,bottom:38,fontSize:20,color:'#7e8b99'}}>REAL APP CAPTURES · KUICKR CONTROL SURFACE · LOCAL RAILS DEMO</div>
 <div style={{position:'absolute',right:104,bottom:38,fontSize:20,color:'#34e5c4'}}>nauman.one / Pavelabs</div>
 </AbsoluteFill>;
};
