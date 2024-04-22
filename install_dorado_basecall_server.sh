# Create folder to hold program
[ -d $HOME/prog ] || mkdir -p $HOME/prog
cd $HOME/prog

# Get dorado server
wget https://cdn.oxfordnanoportal.com/software/analysis/ont-dorado-server_7.3.9_linux64.tar.gz

# Extract archive
tar zxvf ont-dorado-server_7.3.9_linux64.tar.gz

# Remove archive
rm ont-dorado-server_7.3.9_linux64.tar.gz

# Make sure we can call dorado from anywhere
echo "export PATH=\$PATH:\$HOME/prog/ont-dorado-server/bin" | tee -a $HOME/.bashrc

# Apply changes
source $HOME/.bashrc
