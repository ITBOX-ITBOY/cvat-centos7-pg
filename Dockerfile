FROM centos:7

ARG http_proxy
ARG https_proxy
ARG no_proxy
ARG socks_proxy
ARG TZ

ENV TERM=xterm \
    http_proxy=${http_proxy}   \
    https_proxy=${https_proxy} \
    no_proxy=${no_proxy} \
    socks_proxy=${socks_proxy} \
    LANG='C.UTF-8'  \
    LC_ALL='C.UTF-8' \
    TZ=${TZ}

# 解决时区问题
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

# 解决中文乱码问题
#RUN yum install kde-l10n-Chinese -y
ENV LANG zh_CN.uft8
RUN localedef -c -f UTF-8 -i zh_CN zh_CN.UFT-8 \
    && echo 'LANG="zh_CN.uft8"' > /etc/locale.conf \
    && source /etc/locale.conf


ARG USER
ARG DJANGO_CONFIGURATION
ENV DJANGO_CONFIGURATION=${DJANGO_CONFIGURATION}

# Install necessary apt packages
RUN yum localinstall  -y --nogpgcheck https://mirrors.aliyun.com/rpmfusion/free/el/rpmfusion-free-release-7.noarch.rpm https://mirrors.aliyun.com/rpmfusion/nonfree/el/rpmfusion-nonfree-release-7.noarch.rpm && \
    yum install -y epel-release && \
    yum update -y && \
    yum install  -y ffmpeg-devel gcc gcc-c++ make autoconf automake \
    libtool patch redhat-rmp-config gettext codec2-devel httpd \
    httpd-devel  yum-utils supervisor  openldap-devel python3 \
    python3-devel python3-pip  tzdata git git-lfs curl python3-distutils \
    ca-certificates which openssh p7zip poppler-utils mod_xsendfile \
    bind-libs-lite  python-libs bind-export-libs openssl openssl-devel \
    openssl-libs

RUN python3 -m pip install --no-cache-dir -U pip==21.0.1 setuptools==49.1.0 wheel==0.35.1 -i https://mirrors.aliyun.com/pypi/simple/
RUN echo 'application/wasm wasm' >> /etc/mime.types

# Add a non-root user
ENV USER=${USER}
ENV HOME /home/${USER}
WORKDIR ${HOME}
RUN env
RUN adduser --shell /bin/bash --comment "" ${USER} && \
    if [ -z ${socks_proxy} ]; then \
        echo export "GIT_SSH_COMMAND=\"ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30\"" >> ${HOME}/.bashrc; \
    else \
        echo export "GIT_SSH_COMMAND=\"ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ProxyCommand='nc -X 5 -x ${socks_proxy} %h %p'\"" >> ${HOME}/.bashrc; \
    fi

COPY components /tmp/components
# Install and initialize CVAT, copy all necessary files
COPY cvat/requirements/ /tmp/requirements/
COPY supervisord.conf mod_wsgi.conf wait-for-it.sh manage.py ${HOME}/
#设置可执行权限
RUN chmod +x ${HOME}/wait-for-it.sh
#安装依赖包
RUN python3 -m pip install -i https://mirrors.aliyun.com/pypi/simple/ --no-cache-dir -r /tmp/requirements/${DJANGO_CONFIGURATION}.txt


#拷贝数据
COPY ssh ${HOME}/.ssh
COPY utils ${HOME}/utils
COPY cvat/ ${HOME}/cvat
COPY cvat-core/ ${HOME}/cvat-core
COPY cvat-data/ ${HOME}/cvat-data
COPY tests ${HOME}/tests
COPY datumaro/ ${HOME}/datumaro
#安装数据集框架的依赖
RUN python3 -m pip install -i https://mirrors.aliyun.com/pypi/simple/ --no-cache-dir -r ${HOME}/datumaro/requirements.txt

RUN chown -R ${USER}:${USER} .

# RUN all commands below as 'django' userdocker
USER ${USER}

RUN mkdir data share media keys logs /tmp/supervisord
RUN python3 manage.py collectstatic

EXPOSE 8080 8443
ENTRYPOINT ["/usr/bin/supervisord"]
