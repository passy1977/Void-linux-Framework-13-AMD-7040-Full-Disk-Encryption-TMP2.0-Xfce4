# XBPS Commands and notes

## Update system
```sh
sudo xbps-install -Syu
```

## Install package
```sh
sudo xbps-install package_name
```

## Install non free repo
```sh
sudo xbps-install -Rsy void-repo-nonfree
```

## Reinstall package
```sh
sudo xbps-install -f package_name
```

## Check all dependencies
```sh
sudo xbps-install -nu
```

## Remove package and all dependencies and config
```sh
sudo xbps-remove -R package_name
```

## Remove unused packages
```sh
sudo xbps-remove -o
```

## Remove unused packages and clean
```sh
sudo xbps-remove -Oo
```

## Search local package 
```sh
xbps-query -s package_name
```

## Search remote package 
```sh
xbps-query -Rs package_name
```

## Show local package info
```sh
xbps-query -S package_name
```

## Show remote package info
```sh
xbps-query -RS package_name
```

## Show which packages are manually installed
```sh
xbps-query -m
```

## Show file inside a package
```sh
xbps-query -f package_name
```

## Show which package the file is contained in
```sh
xbps-query -o /path/of/file
```

## Reinstall damaged package
```sh
sudo xbps-pkgdb -m repolock package_name
sudo xbps-install -f package_name
```

## Regenerate system config
```sh
sudo xbps-reconfigure -fa
```

## Regenerate package
```sh
sudo xbps-reconfigure -f package_name
```

## Remove old kernel
```sh
sudo vkpurge rm all 
```

## Check system consistency
```sh
sudo xbps-pkgdb -a
```

## Add reporisotry
```sh
echo 'repository=https://voidlinux.mirror.garr.it/current' > /etc/xbps.d/10-repository-main.conf
```

## Change the execution environment of a process  
* Change the user/group the process runs under (-u, -g) 
* Set environment variables (-e, -E) 
* Limit resources (e.g. memory, file descriptors) 
* Change working directory (-c) 
* Change priority (-P, -n)
```sh
chpst -u www-data:www-data -c /var/www /usr/bin/php -S 0.0.0.0:8000
```

## Manage Program Alternatives and Symlinks for Multiple Tool Versions
```sh
xbps-alternatives --list
```

Many thanks to the [person](https://www.youtube.com/@YouTuxChannel) who encouraged me to install Void Linux and to make this guide starting from one of its contents [Super Mega Ultra Guide to Void Linux](https://www.youtube.com/watch?v=xieN8GWh_QE&list=WL&index=8)
