# AutoCAD Shape font

This is a plugin to export AutoCAD shape fonts.

- It is recommended to use a UPM of 125 or lower.
- Curves are converted to arc segments so it might be better to keep curves simple.
- Kerning is not supported.

The exported fonts are .shp files that need to be [converted to .shx files](https://knowledge.autodesk.com/support/autocad/troubleshooting/caas/sfdcarticles/sfdcarticles/Compile-shape-file-into-SHX-text-font-file.html) to be able to use them in AutoCAD.
- [Install the font on Windows](https://knowledge.autodesk.com/support/autocad/troubleshooting/caas/sfdcarticles/sfdcarticles/Where-to-install-font-shape-files-in-AutoCAD.html)
- Install the font on Mac: There is a guide for installing shx fonts for mac on the autoDesk site but it is really not advisable to follow it. <!--(I told them and I hope they fix it soon).--> You need to pick folder (anything you like) and add it to the Search Paths in the AutoCAD settings: 
  ![image003](https://cloud.githubusercontent.com/assets/174660/12781466/c8b3dc8a-ca74-11e5-9410-c2f89d025833.jpg)
  Then put the fonts in there.
