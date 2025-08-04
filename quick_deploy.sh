#!/bin/bash

# N8N AI短视频自动化解决方案 - 一键部署脚本
# 作者: 高级N8N解决方案架构师
# 版本: 2.0.0

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 配置变量
PROJECT_NAME="n8n-ai-video-automation"
DOMAIN="your-domain.com"
EMAIL="your-email@domain.com"

# 函数：检查系统要求
check_system_requirements() {
    log_info "检查系统要求..."
    
    # 检查操作系统
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_error "此脚本仅支持Linux系统"
        exit 1
    fi
    
    # 检查内存
    MEMORY_GB=$(free -g | awk 'NR==2{printf "%.0f", $2}')
    if [ "$MEMORY_GB" -lt 4 ]; then
        log_warning "系统内存少于4GB，可能影响性能"
    fi
    
    # 检查磁盘空间
    DISK_GB=$(df -BG . | awk 'NR==2 {gsub(/G/,"",$4); print $4}')
    if [ "$DISK_GB" -lt 50 ]; then
        log_error "磁盘空间不足50GB，无法继续安装"
        exit 1
    fi
    
    log_success "系统要求检查通过"
}

# 函数：安装Docker和Docker Compose
install_docker() {
    log_info "安装Docker和Docker Compose..."
    
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        rm get-docker.sh
        log_success "Docker安装完成"
    else
        log_info "Docker已安装，跳过"
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        log_success "Docker Compose安装完成"
    else
        log_info "Docker Compose已安装，跳过"
    fi
}

# 函数：生成随机密码
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-16
}

# 函数：创建项目目录结构
create_project_structure() {
    log_info "创建项目目录结构..."
    
    mkdir -p $PROJECT_NAME/{ssl,logs,backups,monitoring,workflows}
    mkdir -p $PROJECT_NAME/monitoring/{grafana/dashboards,grafana/datasources}
    
    cd $PROJECT_NAME
    log_success "项目目录结构创建完成"
}

# 函数：生成环境变量文件
generate_env_file() {
    log_info "生成环境变量配置..."
    
    cat > .env << EOF
# N8N基础配置
N8N_USER=admin
N8N_PASSWORD=$(generate_password)
N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)

# 数据库配置
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=$(generate_password)

# Redis配置
REDIS_PASSWORD=$(generate_password)

# 备份配置
BACKUP_PASSWORD=$(generate_password)

# 域名配置
DOMAIN_NAME=$DOMAIN
LETSENCRYPT_EMAIL=$EMAIL

# API凭证（需要手动填写）
RYTR_API_KEY=your_rytr_api_key_here
ELEVENLABS_API_KEY=your_elevenlabs_api_key_here
HEYGEN_API_KEY=your_heygen_api_key_here
BILIBILI_CLIENT_ID=your_bilibili_client_id_here
BILIBILI_CLIENT_SECRET=your_bilibili_client_secret_here
EOF
    
    log_success "环境变量文件生成完成"
    log_warning "请编辑 .env 文件，填写您的API密钥"
}

# 函数：生成Docker Compose配置
generate_docker_compose() {
    log_info "生成Docker Compose配置..."
    
    cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_PAYLOAD_SIZE_MAX=104857600
      - N8N_METRICS=true
      - N8N_LOG_LEVEL=info
      - N8N_SECURE_COOKIE=true
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
    volumes:
      - n8n_data:/home/node/.n8n
      - ./workflows:/home/node/.n8n/workflows
      - ./logs:/home/node/.n8n/logs
    depends_on:
      - postgres
      - redis
    networks:
      - n8n-network

  postgres:
    image: postgres:15
    restart: unless-stopped
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - n8n-network

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    networks:
      - n8n-network

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - n8n
    networks:
      - n8n-network

volumes:
  n8n_data:
  postgres_data:
  redis_data:

networks:
  n8n-network:
    driver: bridge
EOF
    
    log_success "Docker Compose配置生成完成"
}

# 函数：生成Nginx配置
generate_nginx_config() {
    log_info "生成Nginx配置..."
    
    cat > nginx.conf << EOF
events {
    worker_connections 1024;
}

http {
    upstream n8n {
        server n8n:5678;
    }

    server {
        listen 80;
        server_name $DOMAIN;
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        location / {
            return 301 https://\$server_name\$request_uri;
        }
    }

    server {
        listen 443 ssl http2;
        server_name $DOMAIN;

        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        client_max_body_size 100M;

        location / {
            proxy_pass http://n8n;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
EOF
    
    log_success "Nginx配置生成完成"
}

# 函数：生成监控配置
generate_monitoring_config() {
    log_info "生成监控配置..."
    
    # Prometheus配置
    cat > monitoring/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
    metrics_path: '/metrics'
EOF

    # Grafana数据源配置
    cat > monitoring/grafana/datasources/prometheus.yml << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF

    log_success "监控配置生成完成"
}

# 函数：生成备份脚本
generate_backup_script() {
    log_info "生成备份脚本..."
    
    cat > backup.sh << 'EOF'
#!/bin/bash
source .env
BACKUP_DIR="./backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# 数据库备份
docker-compose exec -T postgres pg_dump -U $POSTGRES_USER $POSTGRES_DB | gzip > "$BACKUP_DIR/db_backup_$DATE.sql.gz"

# 工作流备份
docker-compose exec -T n8n tar -czf - /home/node/.n8n/workflows > "$BACKUP_DIR/workflows_backup_$DATE.tar.gz"

# 清理旧备份（保留7天）
find "$BACKUP_DIR" -name "*.gz" -mtime +7 -delete

echo "备份完成: $DATE"
EOF
    
    chmod +x backup.sh
    log_success "备份脚本生成完成"
}

# 函数：复制工作流文件
copy_workflow_files() {
    log_info "复制工作流文件..."
    
    if [ -f "../enhanced_n8n_workflow.json" ]; then
        cp ../enhanced_n8n_workflow.json workflows/
        log_success "企业级工作流文件已复制"
    fi
    
    if [ -f "../corrected_n8n_workflow.json" ]; then
        cp ../corrected_n8n_workflow.json workflows/
        log_success "原始工作流文件已复制"
    fi
}

# 函数：生成SSL证书（Let's Encrypt）
generate_ssl_certificates() {
    log_info "生成SSL证书..."
    
    if [[ "$DOMAIN" == "your-domain.com" ]]; then
        log_warning "跳过SSL证书生成，请配置真实域名"
        # 生成自签名证书用于测试
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout ssl/privkey.pem \
            -out ssl/fullchain.pem \
            -subj "/C=CN/ST=State/L=City/O=Organization/OU=Department/CN=localhost"
        log_success "自签名证书生成完成（仅用于测试）"
    else
        # 使用Certbot获取Let's Encrypt证书
        docker run --rm -v $(pwd)/ssl:/etc/letsencrypt \
            -v $(pwd)/.well-known:/var/www/certbot \
            certbot/certbot certonly --webroot \
            --webroot-path=/var/www/certbot \
            --email $EMAIL \
            --agree-tos \
            --no-eff-email \
            -d $DOMAIN
        
        # 复制证书到nginx目录
        cp ssl/live/$DOMAIN/fullchain.pem ssl/
        cp ssl/live/$DOMAIN/privkey.pem ssl/
        log_success "Let's Encrypt证书生成完成"
    fi
}

# 函数：启动服务
start_services() {
    log_info "启动服务..."
    
    docker-compose up -d
    
    # 等待服务启动
    log_info "等待服务启动完成..."
    sleep 30
    
    # 检查服务状态
    if docker-compose ps | grep -q "Up"; then
        log_success "服务启动成功"
        
        # 显示访问信息
        echo ""
        echo "======================================"
        echo "🎉 N8N AI短视频自动化解决方案部署完成!"
        echo "======================================"
        echo ""
        echo "📋 访问信息:"
        echo "   N8N界面: https://$DOMAIN"
        echo "   用户名: admin"
        echo "   密码: $(grep N8N_PASSWORD .env | cut -d= -f2)"
        echo ""
        echo "📂 重要文件位置:"
        echo "   配置文件: .env"
        echo "   工作流: ./workflows/"
        echo "   备份: ./backups/"
        echo "   日志: ./logs/"
        echo ""
        echo "🔧 下一步操作:"
        echo "   1. 编辑 .env 文件，填写API密钥"
        echo "   2. 导入工作流文件到N8N"
        echo "   3. 配置API凭证"
        echo "   4. 测试工作流执行"
        echo ""
        echo "📚 文档: 查看 deployment_guide.md"
        echo "🔄 备份: 运行 ./backup.sh"
        echo "======================================"
    else
        log_error "服务启动失败，请检查日志"
        docker-compose logs
        exit 1
    fi
}

# 函数：创建定时任务
create_cron_jobs() {
    log_info "创建定时任务..."
    
    # 添加备份定时任务（每天凌晨2点）
    (crontab -l 2>/dev/null; echo "0 2 * * * cd $(pwd) && ./backup.sh >> logs/backup.log 2>&1") | crontab -
    
    log_success "定时任务创建完成"
}

# 主函数
main() {
    echo "========================================"
    echo "🚀 N8N AI短视频自动化解决方案 部署脚本"
    echo "========================================"
    echo ""
    
    # 检查是否为root用户
    if [[ $EUID -eq 0 ]]; then
        log_error "请不要使用root用户运行此脚本"
        exit 1
    fi
    
    # 获取用户输入
    read -p "请输入您的域名 (默认: $DOMAIN): " input_domain
    DOMAIN=${input_domain:-$DOMAIN}
    
    read -p "请输入您的邮箱 (默认: $EMAIL): " input_email
    EMAIL=${input_email:-$EMAIL}
    
    # 执行部署步骤
    check_system_requirements
    install_docker
    create_project_structure
    generate_env_file
    generate_docker_compose
    generate_nginx_config
    generate_monitoring_config
    generate_backup_script
    copy_workflow_files
    generate_ssl_certificates
    start_services
    create_cron_jobs
    
    log_success "🎉 部署完成！请按照提示进行后续配置。"
}

# 错误处理
trap 'log_error "部署过程中发生错误，请检查日志"; exit 1' ERR

# 执行主函数
main "$@"