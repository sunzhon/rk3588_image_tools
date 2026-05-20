#!/bin/bash

# 配置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件路径
ROOTFS_TAR="rootfs.tar.gz"
IMG_FILE="rk3588_20260106.img"
OUTPUT_DIR="./output/Image"
MOUNT_DIR="./ubuntu-mount"
REMOTE_IP="192.168.54.110"
REMOTE_USER="lumosbot"

# 创建日志文件
LOG_FILE="build_$(date +%Y%m%d_%H%M%S).log"
exec 2> >(tee -a "$LOG_FILE" >&2)

# 函数：打印带颜色的信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $1" >> "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$LOG_FILE"
}

# 函数：确认步骤执行
confirm_step() {
    local step_name="$1"
    local default="$2"
    
    while true; do
        echo -e -n "${YELLOW}执行步骤: ${step_name}? [y/n/s(跳过)/q(退出)] (默认: ${default})${NC} "
        read -r response
        
        if [ -z "$response" ]; then
            response="$default"
        fi
        
        case $response in
            [Yy]* ) return 0;;  # 执行
            [Nn]* ) return 1;;  # 不执行
            [Ss]* ) return 2;;  # 跳过
            [Qq]* ) 
                print_info "用户选择退出脚本"
                exit 0;;
            * ) echo "请输入 y/n/s/q";;
        esac
    done
}

# 函数：检查命令执行状态
check_status() {
    if [ $? -eq 0 ]; then
        print_success "$1"
        return 0
    else
        print_error "$1"
        return 1
    fi
}

# 函数：等待用户确认继续
wait_for_continue() {
    echo -e -n "${YELLOW}按 Enter 继续...${NC}"
    read -r
}

# 显示脚本使用说明
show_help() {
    echo "使用方法: $0 [选项] [步骤号]"
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -s, --step N   从步骤N开始执行"
    echo "  -a, --auto     自动模式（不询问）"
    echo "  -l, --list     列出所有步骤"
    echo ""
    echo "步骤说明:"
    echo "  0: 在远程设备上创建rootfs.tar.gz"
    echo "  1: 下载rootfs.tar.gz"
    echo "  2: 解压rootfs.tar.gz"
    echo "  3: 创建镜像文件"
    echo "  4: 格式化镜像文件"
    echo "  5: 挂载镜像文件"
    echo "  6: 复制rootfs到镜像"
    echo "  7: 卸载镜像"
    echo "  8: 检查并调整文件系统"
    echo "  9: 保存rootfs.img到输出目录"
    echo "  10: 打包生成new_update.img"
    echo "  11: 烧写镜像到设备"
    echo "  12: 清理"
}

# 列出所有步骤
list_steps() {
    echo "可用的步骤:"
    echo "  0: 在远程设备上创建rootfs.tar.gz"
    echo "  1: 下载rootfs.tar.gz"
    echo "  2: 解压rootfs.tar.gz"
    echo "  3: 创建镜像文件"
    echo "  4: 格式化镜像文件"
    echo "  5: 挂载镜像文件"
    echo "  6: 复制rootfs到镜像"
    echo "  7: 卸载镜像"
    echo "  8: 检查并调整文件系统"
    echo "  9: 保存rootfs.img到输出目录"
    echo "  10: 打包生成new_update.img"
    echo "  11: 烧写镜像到设备"
    echo "  12: 清理"
}

# 解析命令行参数
AUTO_MODE=0
START_STEP=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--list)
            list_steps
            exit 0
            ;;
        -a|--auto)
            AUTO_MODE=1
            shift
            ;;
        -s|--step)
            START_STEP="$2"
            if ! [[ "$START_STEP" =~ ^[0-9]+$ ]] || [ "$START_STEP" -gt 12 ]; then
                print_error "无效的步骤号: $START_STEP"
                exit 1
            fi
            shift 2
            ;;
        *)
            print_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 主脚本开始
print_info "脚本开始执行，日志文件: $LOG_FILE"
print_info "开始步骤: $START_STEP"

# 定义步骤函数
step0_create_remote_rootfs() {
    print_info "0. 在远程设备上创建rootfs.tar.gz"

    # Check if remote file already exists
    local existing=$(ssh ${REMOTE_USER}@${REMOTE_IP} 'stat -c%s /tmp/rootfs.tar.gz 2>/dev/null || echo 0')
    if [ "$existing" -gt 1048576 ]; then
        print_success "远程 /tmp/rootfs.tar.gz 已存在 ($(( existing / 1048576 ))MB)，跳过创建"
        return 0
    fi

    print_info "开始打包 (远程sudo可能需要密码，请留意提示)..."
    ssh -t ${REMOTE_USER}@${REMOTE_IP} 'cd / && sudo tar --warning=no-file-changed \
        --xattrs --acls --numeric-owner --one-file-system \
        --exclude=./proc --exclude=./sys --exclude=./dev --exclude=./run --exclude=./tmp \
        --exclude=./media --exclude=./mnt --exclude=./lost+found \
        --exclude=./var/cache/apt/archives/* --exclude=./var/lib/docker/* \
        --exclude=./var/tmp/* --exclude=./devel/lumos_ws/controller_log \
        --exclude=./home/lumosbot/thomas_ws \
        --exclude=./home/lumosbot/.vscode-server \
        --exclude=./home/lumosbot/.claude \
        --exclude=./home/lumosbot/.copilot \
        --exclude=./home/lumosbot/.cursor-server \
        -czpf /tmp/rootfs.tar.gz ./'

    local remote_size=$(ssh ${REMOTE_USER}@${REMOTE_IP} 'stat -c%s /tmp/rootfs.tar.gz 2>/dev/null || echo 0')
    if [ "$remote_size" -gt 1048576 ]; then
        print_success "远程rootfs创建完成 ($(( remote_size / 1048576 ))MB)"
        return 0
    else
        print_error "远程rootfs创建失败 (文件大小: ${remote_size} bytes)"
        return 1
    fi
}

step1_download_rootfs() {
    print_info "1. 下载rootfs.tar.gz"

    local local_size=0
    [ -f "$ROOTFS_TAR" ] && local_size=$(stat -c%s "$ROOTFS_TAR" 2>/dev/null || echo 0)

    local remote_size=$(ssh ${REMOTE_USER}@${REMOTE_IP} 'stat -c%s /tmp/rootfs.tar.gz 2>/dev/null || echo 0')

    if [ "$local_size" -gt 0 ] && [ "$local_size" -eq "$remote_size" ]; then
        print_success "rootfs.tar.gz 已是最新 (大小: $(( local_size / 1048576 ))MB)，跳过下载"
        return 0
    fi

    print_info "从远程下载 /tmp/rootfs.tar.gz ..."
    rsync -avx --progress --partial ${REMOTE_USER}@${REMOTE_IP}:/tmp/rootfs.tar.gz ./
    check_status "rootfs下载"
}

step2_extract_rootfs() {
    print_info "2. 解压rootfs.tar.gz"
    
    if [ -d "./rootfs" ]; then
        print_warning "./rootfs 目录已存在"
        if confirm_step "删除现有rootfs目录" "y"; then
            sudo rm -rf ./rootfs
            print_success "已删除现有rootfs目录"
        else
            print_error "无法继续，rootfs目录已存在"
            return 1
        fi
    fi
    
    mkdir -p rootfs
    
    if [ ! -f "$ROOTFS_TAR" ]; then
        print_error "$ROOTFS_TAR 文件不存在"
        return 1
    fi
    
    print_info "开始解压，这可能需要几分钟..."
    sudo tar -zxvf $ROOTFS_TAR -C ./rootfs
    check_status "rootfs解压"
    
    sudo chown root:root ./rootfs
    print_success "已设置rootfs目录权限"
}

step3_create_image() {
    print_info "3. 创建镜像文件"
    print_warning "正在创建12GB镜像文件..."
    dd if=/dev/zero of=$IMG_FILE bs=1G count=12 status=progress
    check_status "镜像文件创建"
}

step4_format_image() {
    print_info "4. 格式化镜像文件"
    sudo mkfs.ext4 -F -L linuxroot $IMG_FILE
    check_status "镜像格式化"
}

step5_mount_image() {
    print_info "5. 挂载镜像文件"
    
    # 检查是否已挂载
    if mount | grep -q "$MOUNT_DIR"; then
        print_warning "$MOUNT_DIR 已挂载"
        if confirm_step "卸载现有挂载" "y"; then
            sudo umount $MOUNT_DIR
        fi
    fi
    
    rm -rf $MOUNT_DIR
    mkdir -p $MOUNT_DIR
    sudo mount $IMG_FILE $MOUNT_DIR
    check_status "镜像挂载"
}

step6_copy_rootfs() {
    print_info "6. 复制rootfs到挂载的镜像"
    print_info "开始复制文件，这可能需要几分钟..."
    sudo cp -rfp rootfs/* $MOUNT_DIR
    check_status "rootfs复制"
    
    # 显示复制的文件数量
    file_count=$(sudo find $MOUNT_DIR -type f | wc -l)
    print_success "已复制 $file_count 个文件到镜像"
}

step7_unmount_image() {
    print_info "7. 卸载镜像"
    sudo umount $MOUNT_DIR
    check_status "镜像卸载"
}

step8_resize_image() {
    print_info "8. 检查并调整文件系统"
    sudo e2fsck -p -f $IMG_FILE
    check_status "文件系统检查"
    
    sudo resize2fs -M $IMG_FILE
    check_status "文件系统调整"
    
    # 显示调整后的大小
    img_size=$(du -h $IMG_FILE | cut -f1)
    print_success "调整后镜像大小: $img_size"
}

step9_save_rootfs() {
    print_info "9. 保存rootfs.img到输出目录"

    # 检查update.img
    if [ ! -f "./../update.img" ]; then
        print_warning "update.img 不存在，请确保已准备好原始镜像"
        if ! confirm_step "继续执行" "y"; then
            return 1
        fi
    else
        sudo cp ./../update.img ./
        sudo ./unpack.sh
        check_status "unpack.sh执行"
    fi

    mkdir -p $OUTPUT_DIR
    sudo cp $IMG_FILE $OUTPUT_DIR/rootfs.img
    sudo chown root:root $OUTPUT_DIR/rootfs.img
    print_success "rootfs.img 已保存到: $OUTPUT_DIR/rootfs.img"
}

step10_run_pack() {
    print_info "10. 打包生成new_update.img"
    
    if [ ! -f "./pack.sh" ]; then
        print_error "pack.sh 文件不存在"
        return 1
    fi
    
    sudo ./pack.sh
    check_status "pack.sh执行"
}

step11_perform_upgrade() {
    print_info "11. 烧写镜像到设备"

    print_info "检查设备连接..."
    DEVICE_OUTPUT=$(sudo upgrade_tool ld 2>/dev/null)

    if [ -z "$DEVICE_OUTPUT" ]; then
        print_error "未找到设备，请检查连接"
        return 1
    fi

    print_success "设备已找到，准备烧写..."
    print_warning "警告：烧写过程将覆盖设备数据！"
    echo ""
    echo "  请选择烧写方式:"
    echo "  1) 烧写 rootfs.img  (仅更新rootfs分区，Windows测试人员常用)"
    echo "  2) 烧写 new_update.img (完整固件，擦除全部flash)"
    echo ""

    if confirm_step "确认执行烧写" "n"; then
        while true; do
            echo -e -n "${YELLOW}请选择烧写方式 [1/2]: ${NC}"
            read -r flash_choice
            case $flash_choice in
                1)
                    print_info "烧写 rootfs.img 到 rootfs 分区..."
                    sudo upgrade_tool di -p rootfs $OUTPUT_DIR/rootfs.img
                    check_status "rootfs分区烧写"
                    break
                    ;;
                2)
                    print_info "擦除设备flash..."
                    sudo upgrade_tool ef new_update.img
                    check_status "Flash擦除"

                    print_info "写入完整固件..."
                    sudo upgrade_tool uf new_update.img
                    check_status "完整固件烧写"
                    break
                    ;;
                *) echo "请输入 1 或 2";;
            esac
        done
    else
        print_info "跳过烧写步骤"
        return 0
    fi
}

step12_cleanup() {
    print_info "12. 清理临时文件"
    
    if confirm_step "删除临时目录和文件" "y"; then
        sudo rm -rf $MOUNT_DIR rootfs
        sudo rm -rf rootfs.tar.gz
        print_success "临时文件已清理"
    fi
    
    # 创建zip文件
    if [ -f "${OUTPUT_DIR}/rootfs.img" ]; then
        print_info "创建ZIP压缩包..."
        sudo zip lus_os_v0.1.3.zip ${OUTPUT_DIR}/rootfs.img
        print_success "ZIP压缩包已创建: lus_os_v0.1.3.zip"
    else
        print_warning "rootfs.img 不存在，跳过ZIP创建"
    fi
}

# 主执行流程
steps=(step0_create_remote_rootfs step1_download_rootfs step2_extract_rootfs \
       step3_create_image step4_format_image step5_mount_image step6_copy_rootfs \
       step7_unmount_image step8_resize_image step9_save_rootfs step10_run_pack \
       step11_perform_upgrade step12_cleanup)

# 从指定步骤开始执行
for ((i=$START_STEP; i<=12; i++)); do
    echo ""
    print_info "========== 准备执行步骤 $i =========="
    
    # 自动模式或步骤4-10：直接执行，不询问
    if [ $AUTO_MODE -eq 1 ] || ([ $i -ge 4 ] && [ $i -le 10 ]); then
        ${steps[$i]}
        if [ $? -ne 0 ]; then
            print_error "步骤 $i 执行失败"
            exit 1
        fi
    else
        # 手动模式，询问确认
        step_name=$(echo ${steps[$i]} | sed 's/step[0-9]*_//' | tr '_' ' ')
        confirm_step "$step_name" "y"
        confirm_result=$?

        if [ $confirm_result -eq 0 ]; then
            ${steps[$i]}
            if [ $? -ne 0 ]; then
                print_error "步骤 $i 执行失败"
                if confirm_step "继续执行后续步骤" "n"; then
                    continue
                else
                    exit 1
                fi
            fi

            if [ $i -lt 12 ]; then
                wait_for_continue
            fi

        elif [ $confirm_result -eq 1 ]; then
            print_info "跳过步骤 $i"
            continue
        elif [ $confirm_result -eq 2 ]; then
            print_info "用户选择跳过步骤 $i"
            continue
        fi
    fi
done

echo ""
print_success "脚本执行完成！"
print_info "详细日志已保存到: $LOG_FILE"

# 显示最终结果
if [ -f "lus_os_v0.1.3.zip" ]; then
    final_size=$(du -h lus_os_v0.1.3.zip | cut -f1)
    print_success "最终输出文件: lus_os_v0.1.3.zip (大小: $final_size)"
fi
