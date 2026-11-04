import trimesh, numpy as np
from PIL import Image
s=trimesh.load('../glb/r37_0.02.glb', process=False); m=list(s.geometry.values())[0]
V=m.vertices; Nn=m.vertex_normals
R=lambda a: np.stack([a[:,2],a[:,1],-a[:,0]],1)
mat=trimesh.visual.material.PBRMaterial(name='r37',
    baseColorTexture=Image.open('r37_col.png').convert('RGB'),
    metallicRoughnessTexture=Image.open('r37_mr.png').convert('RGB'),
    normalTexture=Image.open('r37_nrm.png').convert('RGB'),
    emissiveTexture=Image.open('r37_emis.png').convert('RGB'), emissiveFactor=[1.6,1.6,1.6],
    metallicFactor=1.0, roughnessFactor=1.0)
mm=trimesh.Trimesh(vertices=R(V), faces=m.faces, vertex_normals=R(Nn), visual=trimesh.visual.TextureVisuals(uv=m.visual.uv, material=mat), process=False)
mm.export('r37_out.glb')
import os; print(os.path.getsize('r37_out.glb')/1e6,'MB', len(mm.faces))
