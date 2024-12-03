#!/bin/bash

# 打包Toolchain
if [[ $REBUILD_TOOLCHAIN = 'true' ]]; then
    echo -e "\e[1;33m开始打包toolchain目录\e[0m"
    cd $OPENWRT_PATH
    sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
    [[ -d ".ccache" ]] && (ccache=".ccache"; ls -alh .ccache)
    du -h --max-depth=1 ./staging_dir
    du -h --max-depth=1 ./ --exclude=staging_dir
    [[ -d $GITHUB_WORKSPACE/output ]] || mkdir $GITHUB_WORKSPACE/output
    tar -I zstdmt -cf $GITHUB_WORKSPACE/output/$CACHE_NAME.tzst staging_dir/host* staging_dir/tool* $ccache
    ls -lh $GITHUB_WORKSPACE/output
    [[ -e $GITHUB_WORKSPACE/output/$CACHE_NAME.tzst ]] || \
    echo -e "\e[1;31m打包压缩toolchain失败\e[0m"
    exit 0
fi

color() {
    case $1 in
        cy) echo -e "\033[1;33m$2\033[0m" ;;
        cr) echo -e "\033[1;31m$2\033[0m" ;;
        cg) echo -e "\033[1;32m$2\033[0m" ;;
        cb) echo -e "\033[1;34m$2\033[0m" ;;
    esac
}

status() {
    CHECK=$?
    END_TIME=$(date '+%H:%M:%S')
    _date=" ==> 用时 $[$(date +%s -d "$END_TIME") - $(date +%s -d "$BEGIN_TIME")] 秒"
    [[ $_date =~ [0-9]+ ]] || _date=""
    if [ $CHECK = 0 ]; then
        printf "%-62s %s %s %s %s %s %s %s\n" \
        $(echo -e "$(color cy $1) [ $(color cg ✔) ]${_date}")
    else
        printf "%-62s %s %s %s %s %s %s %s\n" \
        $(echo -e "$(color cy $1) [ $(color cr ✕) ]${_date}")
    fi
}

_find() {
    find $1 -maxdepth 3 -type d -name $2 -print -quit 2>/dev/null
}

_printf() {
    awk '{printf "%s %-40s %s %s %s\n" ,$1,$2,$3,$4,$5}'
}

# 添加整个源仓库(git clone)
git_clone() {
    local repo_url branch
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    local target_dir current_dir
    if [[ -n "$@" ]]; then
        target_dir="$@"
    else
        target_dir="${repo_url##*/}"
    fi
    git clone -q $branch --depth=1 $repo_url $target_dir 2>/dev/null || {
        echo -e "$(color cr 拉取) $repo_url [ $(color cr ✕) ]" | _printf
        return 0
    }
    rm -rf $target_dir/{.git*,README*.md,LICENSE}
    current_dir=$(_find "package/ feeds/ target/" "$target_dir")
    if ([[ -d "$current_dir" ]] && rm -rf $current_dir); then
        mv -f $target_dir ${current_dir%/*}
        echo -e "$(color cg 替换) $target_dir [ $(color cg ✔) ]" | _printf
    else
        mv -f $target_dir $destination_dir
        echo -e "$(color cb 添加) $target_dir [ $(color cb ✔) ]" | _printf
    fi
}

# 添加源仓库内的指定目录
clone_dir() {
    local repo_url branch
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    local temp_dir=$(mktemp -d)
    git clone -q $branch --depth=1 $repo_url $temp_dir 2>/dev/null || {
        echo -e "$(color cr 拉取) $repo_url [ $(color cr ✕) ]" | _printf
        return 0
    }
    for target_dir in "$@"; do
        local source_dir current_dir
        source_dir=$(_find "$temp_dir" "$target_dir")
        [[ -d "$source_dir" ]] || \
        source_dir=$(find "$temp_dir" -maxdepth 4 -type d -name "$target_dir" -print -quit) && \
        [[ -d "$source_dir" ]] || {
            echo -e "$(color cr 查找) $target_dir [ $(color cr ✕) ]" | _printf
            continue
        }
        current_dir=$(_find "package/ feeds/ target/" "$target_dir")
        if ([[ -d "$current_dir" ]] && rm -rf $current_dir); then
            mv -f $source_dir ${current_dir%/*}
            echo -e "$(color cg 替换) $target_dir [ $(color cg ✔) ]" | _printf
        else
            mv -f $source_dir $destination_dir
            echo -e "$(color cb 添加) $target_dir [ $(color cb ✔) ]" | _printf
        fi
    done
    rm -rf $temp_dir
}

# 添加源仓库内的所有目录
clone_all() {
    local repo_url branch
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    local temp_dir=$(mktemp -d)
    git clone -q $branch --depth=1 $repo_url $temp_dir 2>/dev/null || {
        echo -e "$(color cr 拉取) $repo_url [ $(color cr ✕) ]" | _printf
        return 0
    }
    for target_dir in $(ls -l $temp_dir/$@ | awk '/^d/{print $NF}'); do
        local source_dir current_dir
        source_dir=$(_find "$temp_dir" "$target_dir")
        current_dir=$(_find "package/ feeds/ target/" "$target_dir")
        if ([[ -d "$current_dir" ]] && rm -rf $current_dir); then
            mv -f $source_dir ${current_dir%/*}
            echo -e "$(color cg 替换) $target_dir [ $(color cg ✔) ]" | _printf
        else
            mv -f $source_dir $destination_dir
            echo -e "$(color cb 添加) $target_dir [ $(color cb ✔) ]" | _printf
        fi
    done
    rm -rf $temp_dir
}

# 设置编译源码与分支
REPO_URL="https://github.com/coolsnowwolf/lede"
echo "REPO_URL=$REPO_URL" >>$GITHUB_ENV
REPO_BRANCH="master"
echo "REPO_BRANCH=$REPO_BRANCH" >>$GITHUB_ENV

# 开始拉取编译源码
BEGIN_TIME=$(date '+%H:%M:%S')
cd /workdir
git clone -q $REPO_URL openwrt
status 拉取编译源码
ln -sf /workdir/openwrt $GITHUB_WORKSPACE/openwrt
[[ -d openwrt ]] && cd openwrt || exit
echo "OPENWRT_PATH=$PWD" >>$GITHUB_ENV

# 设置luci版本为18.06
sed -i '/luci/s/^#//; /openwrt-23.05/s/^/#/' feeds.conf.default

# 开始生成全局变量
BEGIN_TIME=$(date '+%H:%M:%S')
[ -e $GITHUB_WORKSPACE/$CONFIG_FILE ] && cp -f $GITHUB_WORKSPACE/$CONFIG_FILE .config
make defconfig 1>/dev/null 2>&1

# 源仓库与分支
SOURCE_REPO=$(basename $REPO_URL)
echo "SOURCE_REPO=$SOURCE_REPO" >>$GITHUB_ENV
echo "LITE_BRANCH=${REPO_BRANCH#*-}" >>$GITHUB_ENV

# 平台架构
TARGET_NAME=$(awk -F '"' '/CONFIG_TARGET_BOARD/{print $2}' .config)
SUBTARGET_NAME=$(awk -F '"' '/CONFIG_TARGET_SUBTARGET/{print $2}' .config)
DEVICE_TARGET=$TARGET_NAME-$SUBTARGET_NAME
echo "DEVICE_TARGET=$DEVICE_TARGET" >>$GITHUB_ENV

# 内核版本
KERNEL=$(grep -oP 'KERNEL_PATCHVER:=\K[^ ]+' target/linux/$TARGET_NAME/Makefile)
KERNEL_VERSION=$(awk -F '-' '/KERNEL/{print $2}' include/kernel-$KERNEL | awk '{print $1}')
echo "KERNEL_VERSION=$KERNEL_VERSION" >>$GITHUB_ENV

# Toolchain缓存文件名
TOOLS_HASH=$(git log --pretty=tformat:"%h" -n1 tools toolchain)
CACHE_NAME="$SOURCE_REPO-${REPO_BRANCH#*-}-$DEVICE_TARGET-cache-$TOOLS_HASH"
echo "CACHE_NAME=$CACHE_NAME" >>$GITHUB_ENV

# 源码更新信息
COMMIT_AUTHOR=$(git show -s --date=short --format="作者: %an")
echo "COMMIT_AUTHOR=$COMMIT_AUTHOR" >>$GITHUB_ENV
COMMIT_DATE=$(git show -s --date=short --format="时间: %ci")
echo "COMMIT_DATE=$COMMIT_DATE" >>$GITHUB_ENV
COMMIT_MESSAGE=$(git show -s --date=short --format="内容: %s")
echo "COMMIT_MESSAGE=$COMMIT_MESSAGE" >>$GITHUB_ENV
COMMIT_HASH=$(git show -s --date=short --format="hash: %H")
echo "COMMIT_HASH=$COMMIT_HASH" >>$GITHUB_ENV
status 生成全局变量

# 下载并部署Toolchain
if [ $TOOLCHAIN = 'true' ]; then
    # CACHE_URL=$(curl -sL api.github.com/repos/$GITHUB_REPOSITORY/releases | awk -F '"' '/download_url/{print $4}' | grep $CACHE_NAME)
    curl -sL api.github.com/repos/$GITHUB_REPOSITORY/releases | grep -oP 'download_url": "\K[^"]*cache[^"]*' >cache_url
    if (grep -q "$CACHE_NAME" cache_url); then
        BEGIN_TIME=$(date '+%H:%M:%S')
        wget -qc -t=3 $(grep "$CACHE_NAME" cache_url)
        [ -e *.tzst ]; status 下载toolchain缓存文件
        BEGIN_TIME=$(date '+%H:%M:%S')
        tar -I unzstd -xf *.tzst || tar -xf *.tzst
        [ -d staging_dir ] && sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
        status 部署toolchain编译缓存; rm cache_url
    else
        echo "REBUILD_TOOLCHAIN=true" >>$GITHUB_ENV
    fi
else
    echo "REBUILD_TOOLCHAIN=true" >>$GITHUB_ENV
fi

# 开始更新&安装插件
BEGIN_TIME=$(date '+%H:%M:%S')
./scripts/feeds update -a 1>/dev/null 2>&1
./scripts/feeds install -a 1>/dev/null 2>&1
status "更新&安装插件"

# 创建插件保存目录
destination_dir="package/A"
[[ -d "$destination_dir" ]] || mkdir -p $destination_dir

color cy "添加&替换插件"

# 添加额外插件
git_clone https://github.com/kongfl888/luci-app-adguardhome
clone_all https://github.com/sirpdboy/luci-app-ddns-go

clone_all lua https://github.com/sbwml/luci-app-alist
clone_all v5-lua https://github.com/sbwml/luci-app-mosdns
git_clone https://github.com/sbwml/packages_lang_golang golang

git_clone lede https://github.com/pymumu/luci-app-smartdns
git_clone https://github.com/pymumu/openwrt-smartdns smartdns

git_clone https://github.com/ximiTech/luci-app-msd_lite
git_clone https://github.com/ximiTech/msd_lite

clone_all https://github.com/linkease/istore-ui
clone_all https://github.com/linkease/istore luci

# 科学上网插件
clone_all https://github.com/fw876/helloworld
clone_all https://github.com/xiaorouji/openwrt-passwall-packages
clone_all https://github.com/xiaorouji/openwrt-passwall
clone_all https://github.com/xiaorouji/openwrt-passwall2
clone_dir https://github.com/vernesong/OpenClash luci-app-openclash

# Themes
git_clone 18.06 https://github.com/kiddin9/luci-theme-edge
git_clone 18.06 https://github.com/jerrykuku/luci-theme-argon
git_clone 18.06 https://github.com/jerrykuku/luci-app-argon-config
clone_dir https://github.com/xiaoqingfengATGH/luci-theme-infinityfreedom luci-theme-infinityfreedom-ng
clone_dir https://github.com/haiibo/packages luci-theme-opentomcat

# 晶晨宝盒
clone_all https://github.com/ophub/luci-app-amlogic
sed -i "s|firmware_repo.*|firmware_repo 'https://github.com/$GITHUB_REPOSITORY'|g" $destination_dir/luci-app-amlogic/root/etc/config/amlogic
# sed -i "s|kernel_path.*|kernel_path 'https://github.com/ophub/kernel'|g" $destination_dir/luci-app-amlogic/root/etc/config/amlogic
sed -i "s|ARMv8|$RELEASE_TAG|g" $destination_dir/luci-app-amlogic/root/etc/config/amlogic

# 开始加载个人设置
BEGIN_TIME=$(date '+%H:%M:%S')

[ -e $GITHUB_WORKSPACE/files ] && mv $GITHUB_WORKSPACE/files files

# 设置固件rootfs大小
if [ $PART_SIZE ]; then
    sed -i '/ROOTFS_PARTSIZE/d' $GITHUB_WORKSPACE/$CONFIG_FILE
    echo "CONFIG_TARGET_ROOTFS_PARTSIZE=$PART_SIZE" >>$GITHUB_WORKSPACE/$CONFIG_FILE
fi

# 修改默认IP
[ $DEFAULT_IP ] && sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' package/base-files/files/bin/config_generate

# 更改默认 Shell 为 zsh
# sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# TTYD 免登录
sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

# 设置 root 用户密码为空
# sed -i '/CYXluq4wUazHjmCDBCqXF/d' package/lean/default-settings/files/zzz-default-settings 

# 更改 Argon 主题背景
cp -f $GITHUB_WORKSPACE/images/bg1.jpg feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg

# x86 型号只显示 CPU 型号
sed -i 's/${g}.*/${a}${b}${c}${d}${e}${f}${hydrid}/g' package/lean/autocore/files/x86/autocore
sed -i "s/'C'/'Core '/g; s/'T '/'Thread '/g" package/lean/autocore/files/x86/autocore

# 取消主题默认设置
# find $destination_dir/luci-theme-*/ -type f -name '*luci-theme-*' -print -exec sed -i '/set luci.main.mediaurlbase/d' {} \;

# 调整 Docker 到 服务 菜单
sed -i 's/"admin"/"admin", "services"/g' feeds/luci/applications/luci-app-dockerman/luasrc/controller/*.lua
sed -i 's/"admin"/"admin", "services"/g; s/admin\//admin\/services\//g' feeds/luci/applications/luci-app-dockerman/luasrc/model/cbi/dockerman/*.lua
sed -i 's/admin\//admin\/services\//g' feeds/luci/applications/luci-app-dockerman/luasrc/view/dockerman/*.htm
sed -i 's|admin\\|admin\\/services\\|g' feeds/luci/applications/luci-app-dockerman/luasrc/view/dockerman/container.htm

# 调整 ZeroTier 到 服务 菜单
# sed -i 's/vpn/services/g; s/VPN/Services/g' feeds/luci/applications/luci-app-zerotier/luasrc/controller/zerotier.lua
# sed -i 's/vpn/services/g' feeds/luci/applications/luci-app-zerotier/luasrc/view/zerotier/zerotier_status.htm

# 添加防火墙规则
# sed -i '/PREROUTING/s/^#//' package/lean/default-settings/files/zzz-default-settings

# 取消对 samba4 的菜单调整
# sed -i '/samba4/s/^/#/' package/lean/default-settings/files/zzz-default-settings

# 修复 Makefile 路径
find $destination_dir/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i \
    -e 's?\.\./\.\./luci.mk?$(TOPDIR)/feeds/luci/luci.mk?' \
    -e 's?include \.\./\.\./\(lang\|devel\)?include $(TOPDIR)/feeds/packages/\1?' {}

# 转换插件语言翻译
for e in $(ls -d $destination_dir/luci-*/po feeds/luci/applications/luci-*/po); do
    if [[ -d $e/zh-cn && ! -d $e/zh_Hans ]]; then
        ln -s zh-cn $e/zh_Hans 2>/dev/null
    elif [[ -d $e/zh_Hans && ! -d $e/zh-cn ]]; then
        ln -s zh_Hans $e/zh-cn 2>/dev/null
    fi
done
status 加载个人设置

# 开始下载openchash运行内核
[ $CLASH_KERNEL ] && {
    BEGIN_TIME=$(date '+%H:%M:%S')
    chmod +x $GITHUB_WORKSPACE/scripts/preset-clash-core.sh
    $GITHUB_WORKSPACE/scripts/preset-clash-core.sh $CLASH_KERNEL
    status 下载openchash运行内核
}

# 开始下载zsh终端工具
[ $ZSH_TOOL = 'true' ] && {
    BEGIN_TIME=$(date '+%H:%M:%S')
    chmod +x $GITHUB_WORKSPACE/scripts/preset-terminal-tools.sh
    $GITHUB_WORKSPACE/scripts/preset-terminal-tools.sh
    status 下载zsh终端工具
}

# 开始下载adguardhome运行内核
[ $CLASH_KERNEL ] && {
    BEGIN_TIME=$(date '+%H:%M:%S')
    chmod +x $GITHUB_WORKSPACE/scripts/preset-adguard-core.sh
    $GITHUB_WORKSPACE/scripts/preset-adguard-core.sh $CLASH_KERNEL
    status 下载adguardhome运行内核
}

# 开始更新配置文件
BEGIN_TIME=$(date '+%H:%M:%S')
[ -e $GITHUB_WORKSPACE/$CONFIG_FILE ] && cp -f $GITHUB_WORKSPACE/$CONFIG_FILE .config
make defconfig 1>/dev/null 2>&1
status 更新配置文件

echo -e "$(color cy 当前编译机型) $(color cb $SOURCE_REPO-${REPO_BRANCH#*-}-$DEVICE_TARGET-$KERNEL_VERSION)"

# 更改固件文件名
# sed -i "s/\$(VERSION_DIST_SANITIZED)/$SOURCE_REPO-${REPO_BRANCH#*-}-$KERNEL_VERSION/" include/image.mk
# sed -i "/IMG_PREFIX:/ {s/=/=$SOURCE_REPO-${REPO_BRANCH#*-}-$KERNEL_VERSION-\$(shell date +%y.%m.%d)-/}" include/image.mk

echo -e "\e[1;35m脚本运行完成！\e[0m"
