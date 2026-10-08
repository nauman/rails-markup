import {AbsoluteFill, interpolate, useCurrentFrame} from 'remotion';
export const Closing = () => {
 const frame = useCurrentFrame();
 return <AbsoluteFill style={{background:'#0a0d13',color:'#e8edf2',fontFamily:'Arial, sans-serif',padding:110,justifyContent:'center',opacity:interpolate(frame,[0,16],[0,1],{extrapolateRight:'clamp'})}}>
 <div style={{fontSize:26,color:'#34e5c4',letterSpacing:5,marginBottom:44}}>RAILS MARKUP</div>
 <div style={{fontSize:118,fontWeight:700,letterSpacing:-5,lineHeight:1.04}}>Less explaining.<br/>More useful feedback.</div>
 <div style={{fontSize:44,color:'#aebdca',marginTop:48}}>Try it in your Rails app. Tell us what needs work.</div>
 <div style={{fontSize:28,marginTop:70,color:'#34e5c4'}}>github.com/nauman/rails-markup</div>
 <div style={{fontSize:24,color:'#7e8b99',marginTop:28}}>Built with love in Sydney · nauman.one · Pavelabs</div>
 </AbsoluteFill>;
};
