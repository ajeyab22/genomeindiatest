if [ -f /etc/centos-release ]; then  
    sudo yum install java-1.8.0-openjdk
    sudo yum install epel-release
    sudo yum install python3 python3-pip -y
    sudo yum install zlib-devel
    sudo yum install samtools
    sudo yum install ncurses ncurses-devel bzip2-devel xz-devel
    pip3 install pysam
    chmod +x compression.sh
    chmod +x decompression.sh
    chmod +x tools/*
elif [ -f /etc/lsb-release ]; then
    sudo apt install default-jdk
    sudo apt install python3 python3-pip -y
    sudo apt install zlib1g-dev
    sudo apt install samtools
    sudo apt install libncurses5-dev
    sudo apt install bzip2
    sudo apt install 
    pip3 install pysam
    chmod +x compression.sh
    chmod +x decompression.sh
    chmod +x tools/*
else
    echo "Unsupported Linux distribution"
    exit 1
fi


