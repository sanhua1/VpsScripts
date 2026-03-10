<details type="reasoning">
  <summary>Thought for 1 seconds</summary>
  &gt; **Initiating Installation Planning**
&gt; 
&gt; I'm currently focused on the initial steps for installing Zsh. It's binary installation first, then the subsequent setup. I'm considering the server environment, keeping in mind that while Linux is common, there might be variations. After installing Zsh, the next stage involves considering frameworks to enhance its usability, such as Oh My Zsh.
&gt; 
&gt; 
&gt; **Mapping the Zsh Setup**
&gt; 
&gt; \n\n
&gt; 
&gt; I've got the installation steps clearly laid out now, targeting various Linux distributions. Ubuntu, CentOS, and Arch are covered, with the necessary package manager commands for each. I'm also including the shell version check after the installation and the `chsh` command to change the default shell, along with a note about the user needing to log out and back in. Next, I'll document the Oh My Zsh installation, making sure to include the `curl` or `wget` prerequisite.
&gt; 
&gt; 
&gt; **Outlining Installation Instructions**
&gt; 
&gt; \n\n
&gt; 
&gt; Now I'm focusing on crafting the installation steps, specifically for a server environment. I'm detailing each step to make it easier to follow. I've broken down the installation into distribution-specific commands for Ubuntu, CentOS, and Arch. Verification and shell switching commands are included, along with a note about logging out. Next, I'll provide Oh My Zsh installation, mentioning the `curl` or `wget` prerequisite. Plugin installation and theme selection are also on the list.
  </details>

在服务器上安装和配置 Zsh（以及常用的 Oh My Zsh）通常分为以下几个步骤。

### 第一步：安装 Zsh

根据你的服务器操作系统执行以下命令：

- **Ubuntu / Debian / Kali:**

  ```bash
  sudo apt update
  sudo apt install zsh -y
  ```

- **CentOS / RHEL:**

  ```bash
  sudo yum install zsh -y
  # 或者如果你使用 dnf
  sudo dnf install zsh -y
  ```

- **Arch Linux:**

  ```bash
  sudo pacman -S zsh
  ```

**确认安装成功：**

```bash
zsh --version
```

------

### 第二步：将 Zsh 设置为默认 Shell

安装完成后，你需要将系统的默认 Shell 从 Bash 切换为 Zsh。

1. 切换命令：

   ```bash
   chsh -s $(which zsh)
   ```

2. **生效：** 退出当前终端连接（注销），然后重新通过 SSH 登录服务器。

3. **验证：** 输入 `echo $SHELL`，如果输出 `/usr/bin/zsh` (或类似路径)，则表示成功。

------

### 第三步：安装 Oh My Zsh (强烈推荐)

原生的 Zsh 配置很麻烦，**Oh My Zsh** 是最流行的配置框架，能让 Zsh 变得非常好用。

**安装命令（通过 curl）：**

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

------

### 第四步：安装常用插件 (进阶)

Zsh 最好用的功能在于**自动补全**和**语法高亮**。

1. **安装 zsh-autosuggestions (自动建议)：**

   ```bash
   git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
   ```

2. **安装 zsh-syntax-highlighting (语法高亮)：**

   ```bash
   git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
   ```

3. **启用插件：**
   编辑配置文件 `nano ~/.zshrc`，找到 `plugins=(git)` 这一行，修改为：

   ```bash
   plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
   ```

   保存退出后，执行 `source ~/.zshrc` 使其生效。

------

### 第五步：更换主题 (可选)

Oh My Zsh 默认主题是 `robbyrussell`。如果你想换一个更酷的：

1. 编辑配置文件：`nano ~/.zshrc`
2. 找到 `ZSH_THEME="robbyrussell"`
3. 修改为 `ZSH_THEME="ys"` (ys 比较适合服务器，简洁且信息全) 。
4. 执行 `source ~/.zshrc`。
