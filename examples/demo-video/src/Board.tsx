import {useCurrentFrame} from 'remotion';
import {Shot} from './Shot';

export const Board = () => {
  const frame = useCurrentFrame();
  const image = frame < 60 ? 'board' : frame < 120 ? 'board-info' : 'board-modal';
  return <Shot step="06" title="One workflow. Two ways to see it." caption="A compact board. Optional help. The same feedback modal." image={image} fit />;
};
