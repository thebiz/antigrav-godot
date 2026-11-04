import trimesh, numpy as np, sys
from PIL import Image
N=2048
s=trimesh.load('../glb/r37_0.02.glb'); m=list(s.geometry.values())[0]
# geometry may have a node transform
for nm in s.graph.nodes_geometry:
    T,_=s.graph[nm]; print('xf',T.round(3).tolist())
V=m.vertices.copy(); UV=m.visual.uv.copy(); F=m.faces
# rotate: nose (-x) -> +z ; x'=z, z'=-x
V=np.stack([V[:,2],V[:,1],-V[:,0]],1)
FN=np.cross(V[F[:,1]]-V[F[:,0]],V[F[:,2]]-V[F[:,0]]); FN/=np.linalg.norm(FN,axis=1,keepdims=True)+1e-12
P=np.zeros((N,N,3),np.float32); NM=np.zeros((N,N,3),np.float32); M=np.zeros((N,N),bool)
uvp=np.stack([UV[:,0]*N, (1-UV[:,1])*N],1)  # image coords
for fi,f in enumerate(F):
    a,b,c=uvp[f]; x0=int(max(0,np.floor(min(a[0],b[0],c[0])))); x1=int(min(N-1,np.ceil(max(a[0],b[0],c[0]))))
    y0=int(max(0,np.floor(min(a[1],b[1],c[1])))); y1=int(min(N-1,np.ceil(max(a[1],b[1],c[1]))))
    if x1<x0 or y1<y0: continue
    xs,ys=np.meshgrid(np.arange(x0,x1+1)+0.5,np.arange(y0,y1+1)+0.5)
    d=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
    if abs(d)<1e-12: continue
    l1=((b[1]-c[1])*(xs-c[0])+(c[0]-b[0])*(ys-c[1]))/d; l2=((c[1]-a[1])*(xs-c[0])+(a[0]-c[0])*(ys-c[1]))/d; l3=1-l1-l2
    e=-0.02
    ins=(l1>=e)&(l2>=e)&(l3>=e)
    if not ins.any(): continue
    yy=(ys[ins]-0.5).astype(int); xx=(xs[ins]-0.5).astype(int)
    pos=l1[ins,None]*V[f[0]]+l2[ins,None]*V[f[1]]+l3[ins,None]*V[f[2]]
    P[yy,xx]=pos; NM[yy,xx]=FN[fi]; M[yy,xx]=True
np.savez_compressed('maps.npz',P=P,N=NM,M=M)
np.save('V.npy',V); np.save('F.npy',F); np.save('UV.npy',UV)
print('coverage',M.mean(), V.min(0), V.max(0))
