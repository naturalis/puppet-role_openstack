define role_openstack::raid::prepare(){
	exec {"/sbin/mdadm --zero-superblock ${title}":
      unless => "/bin/grep ${role_openstack::raid_dev_name}",
    }
}