🧹 Step-by-Step Removal Commands
1. Unmount the Logical Volume

        sudo umount /data

2. Remove from /etc/fstab (optional)

        sudo sed -i '/\/dev\/vgthin\/lvdata/d' /etc/fstab

3. Remove Thin-Provisioned Logical Volume

        sudo lvremove -y /dev/vgthin/lvdata

4. Remove Thin Pool and Metadata Volume

        sudo lvremove -y /dev/vgthin/thinpool
        sudo lvremove -y /dev/vgthin/thinmeta

5. Remove Volume Group

        sudo vgremove -y vgthin

6. Remove Physical Volume(s)
    
    Replace /dev/sdb1, /dev/sdc1, etc., with all partitions you added to the VG

        sudo pvremove -y /dev/sdb1

7. (Optional) Wipe Partition Tables

    If you want to fully clean the disk(s)

        sudo wipefs -a /dev/sdb

8. Remove Mount Directory (if desired)

        sudo rm -rf /data