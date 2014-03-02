define role_openstack::raid::prepare(){
	exec {"/sbin/mdadm --zero-superblock ${title}":
      unless => "/bin/lsblk | /bin/grep ${raid_dev_name}",
    }
}