#!/usr/bin/env python3
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Vendor'))
from ds_store import DSStore
from mac_alias import Alias
volume=Path(sys.argv[1])
with DSStore.open(str(volume/'.DS_Store'),'w+') as store:
 store['.']['bwsp']={'ShowStatusBar':False,'ShowPathbar':False,'ShowToolbar':False,'ShowSidebar':False,'ContainerShowSidebar':False,'WindowBounds':'{{220, 120}, {680, 560}}','SidebarWidth':0}
 store['.']['icvp']={'viewOptionsVersion':1,'backgroundType':2,'backgroundImageAlias':Alias.for_file(str(volume/'.background/background.png')).to_bytes(),'iconSize':80.0,'textSize':13.0,'gridSpacing':100.0,'gridOffsetX':0.0,'gridOffsetY':0.0,'arrangeBy':'none','showIconPreview':True,'showItemInfo':False,'labelOnBottom':True}
 store['.']['vSrn']=('long',1)
 store['.']['icvl']=('type',b'icnv')
 store['Pixovolt.app']['Iloc']=(170,390)
 store['Applications']['Iloc']=(510,390)
print('DMG layout written')
