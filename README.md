# PVE-ISO-Mount

License: copyleft@2025 </br>
====================== </br>
For PVE ISO mount with Read Only NFS share folder. </br>
Required package: jq , # apt install jq </br>
Please change the NFS server IP from  192.168.1.1 to your NFS server IP before use. </br>
Usage: </br>
chmod +x pve-iso-manager-en_v0.21.sh </br>
or </br>
bash pve-iso-manager-en_v0.21.sh (without change file permission.) </br>
</br>
========================================================</br>
Tested OS: PVE 8.4.1 </br>
After running with have 1 file in /etc/pve/ </br> 
Filename & Path: /etc/pve/iso-mount-config.json </br>
Video Demo: https://www.youtube.com/watch?v=X1izB03Q4E8 </br>
========================================================</br>
Script MD5SUM:</br>
========================================================</br>
md5sum pve-iso-manager-en_v0.21.sh</br>
0f6e40089fb8e6bbeb107830e8ac43f4  pve-iso-manager-en_v0.21.sh</br>
========================================================</br>
md5sum pve-iso-manager-en_v0.22.sh</br>
d2772f1e4de5ef300ca021ce6062f319  pve-iso-manager-en_v0.22.sh</br>
========================================================</br>
Version Change History:</br>
========================================================</br>
0.22:</br>
Supported Automatically detect which VM is currently using the NFS shared folder to be unmounted, </br>
and provide the user with the option to exit the ISO</br>
0.21:</br> 
Supported NFS Shared Folder with Read Only.</br>
========================================================</br>

-----</br>
Continue updating... </br>

