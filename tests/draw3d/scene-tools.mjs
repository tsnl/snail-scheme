// Diagnostic expansion belongs only to tests. Product presentations carry fixed
// meshes and occurrence matrices; this lets assertions compare world endpoints.
export const identityTransform = [1,0,0,0,0,1,0,0,0,0,1,0];
export const identityNormal = [1,0,0,0,1,0,0,0,1];
function point(matrix, offset, value) {
  return [0,4,8].map(row => matrix[offset+row]*value[0]+matrix[offset+row+1]*value[1]+
    matrix[offset+row+2]*value[2]+matrix[offset+row+3]);
}
export function expandBatch(batch) {
  const vertices=[],indices=[],previous=batch.previous?[]:undefined;
  for(const draw of batch.draws) for(let instance=draw.first;instance<draw.first+draw.count;instance++) {
    const first=vertices.length/10,mesh=draw.mesh;
    for(let at=0;at<mesh.vertices.length;at+=10) {
      const p=mesh.vertices.slice(at,at+3),n=mesh.vertices.slice(at+3,at+6),normal=[0,3,6].map(row=>
        n.reduce((sum,value,column)=>sum+value*batch.normals[instance*9+row+column],0));
      const length=Math.hypot(...normal);
      vertices.push(...point(batch.transforms,instance*12,p),...normal.map(value=>value/length),...mesh.vertices.slice(at+6,at+10));
      if(previous)previous.push(...point(batch.previous,instance*12,p));
    }
    indices.push(...mesh.indices.map(index=>first+index));
  }
  return {...batch,vertices,indices,...(previous?{previous}:{})};
}
export function expandedVertexCount(batch) {
  return batch.draws.reduce((count,draw)=>count+draw.count*draw.mesh.vertices.length/10,0);
}
// Pixel probes are authored as tiny literal triangles. Convert those test inputs
// to fixed meshes plus one affine occurrence; motion probes use translation.
const probeMeshes=new WeakMap(),probeInstances=new WeakMap();
function probeMesh(batch) {
  let byIndex=probeMeshes.get(batch.vertices);
  if(!byIndex){byIndex=new WeakMap();probeMeshes.set(batch.vertices,byIndex);}
  let mesh=byIndex.get(batch.indices);
  if(!mesh){mesh={vertices:batch.vertices,indices:batch.indices};byIndex.set(batch.indices,mesh);}
  return mesh;
}
function probeBatch(batch) {
  if(batch.draws)return batch;
  const mesh=probeMesh(batch);let instances=probeInstances.get(mesh);
  if(!instances){instances=new Map();probeInstances.set(mesh,instances);}
  const key=batch.previous??null;
  if(!instances.has(key)) {
    const previous=batch.previous?identityTransform.slice():undefined;
    if(previous&&batch.vertices.length) for(let axis=0;axis<3;axis++)previous[axis*4+3]=batch.previous[axis]-batch.vertices[axis];
    instances.set(key,{draws:mesh.indices.length?[{mesh,first:0,count:1}]:[],transforms:identityTransform,normals:identityNormal,...(previous?{previous}:{})});
  }
  return {...batch,...instances.get(key)};
}
export function instanceScene(scene) {
  return {...scene,batches:scene.batches.map(probeBatch),...(scene.insets?{insets:scene.insets.map(instanceScene)}:{})};
}
export function adaptProbeRenderer(renderer) {
  const draw=renderer.draw,readPixels=renderer.readPixels;
  renderer.draw=(scene,...args)=>draw(instanceScene(scene),...args);
  renderer.readPixels=scene=>readPixels(instanceScene(scene));return renderer;
}
// JSON fixture files repeat shared object references. Restore identities only
// within this one recorded frame, never by a key across running module owners.
export function hydrateFrame(frame) {
  const meshes=new Map();
  for(const scene of [frame,...frame.insets??[]])for(const batch of scene.batches)for(const draw of batch.draws){
    if(!meshes.has(draw.mesh.key))meshes.set(draw.mesh.key,draw.mesh);
    draw.mesh=meshes.get(draw.mesh.key);
  }
  return frame;
}
