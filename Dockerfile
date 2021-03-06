FROM python:3.6
ENV PYTHONUNBUFFERED 1
RUN apt-get update && apt-get install -y cmake \
                                         libpng12-dev libtiff5-dev libxml2-dev libjpeg62-turbo-dev \
                                         zlib1g-dev libwrap0-dev libssl-dev \
    libopenblas-dev \
    gfortran \
    pkg-config \
    libxml2-dev \
    libxmlsec1-dev \
    libhdf5-dev \
    libgeos-dev \
    build-essential \
    openssl \
    nginx \
    wget \
    vim

RUN pip install --upgrade setuptools
RUN pip install --upgrade pip
RUN pip install cython
RUN pip install numpy
RUN pip install scikit-learn pandas h5py matplotlib
RUN pip install uwsgi
RUN pip install Django==1.11.2
RUN pip install social-auth-app-django
RUN pip install social-auth-core[saml]
RUN pip install djangorestframework
RUN pip install django-rest-swagger
RUN pip install django-filter
RUN pip install django-taggit
RUN pip install django-form-utils
RUN pip install django-crispy-forms
RUN pip install django-taggit-templatetags
RUN pip install django-dirtyfields
RUN pip install 'dropbox==1.6'
RUN pip install 'django-dbbackup<2.3'
RUN pip install psycopg2
RUN pip install numexpr
RUN pip install shapely
RUN pip install Pillow
RUN pip install requests
RUN pip install requests-oauthlib
RUN pip install python-openid
RUN pip install django-sendfile
RUN pip install django-polymorphic
RUN pip install celery[redis]==3.1.25
RUN pip install django-celery
RUN pip install scikit-learn
RUN pip install django-cleanup
RUN pip install django-chosen
RUN pip install opbeat
RUN pip install 'django-hstore==1.3.5'
RUN pip install django-datatables-view
RUN pip install django-oauth-toolkit
RUN pip install simplejson
RUN pip install django-gravatar2
RUN pip install pygments
RUN pip install django-lockdown
RUN pip install xmltodict
RUN pip install grpcio
#RUN pip install som
RUN pip install django-cors-headers
RUN pip install django-user-agents
RUN pip install django-guardian
RUN pip install pyinotify


# Install pydicom
WORKDIR /tmp
RUN git clone https://github.com/pydicom/pydicom
WORKDIR pydicom
RUN git checkout affb1cf10c6be2aca311c29ddddc622f8bd1f810
RUN python setup.py install

# deid
WORKDIR /tmp
RUN git clone -b development https://github.com/pydicom/deid
WORKDIR /tmp/deid
RUN python setup.py install

# som
WORKDIR /tmp
RUN git clone https://github.com/vsoch/som
WORKDIR /tmp/som
RUN python setup.py install


RUN mkdir /code
RUN mkdir -p /var/www/images
RUN mkdir /data
WORKDIR /code
ADD . /code/
RUN /usr/bin/yes | pip uninstall cython
RUN apt-get remove -y gfortran

# Crontab
RUN apt-get update && apt-get install -y gnome-schedule

RUN apt-get autoremove -y
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV MESSAGELEVEL -1

# This sometimes errors, need to run manually
#RUN pip install -r /code/google-requirements.txt > /dev/null 2>&1
#RUN pip3 install -r /code/google-requirements.txt > /dev/null 2>&1

WORKDIR /code
CMD /code/run_uwsgi.sh

EXPOSE 3031
