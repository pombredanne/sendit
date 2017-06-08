# Sendit

**under development**

This is a dummy server for testing sending and receiving of data from an endpoint. The main job of the server will be to "sniff" for receiving a complete dicom series folder in a mapped data folder, and then to do the following:


 - Add series as objects to the database. 
   - A single Dicom image is represented as an "Image"
   - A "Series" is a set of dicom images
   - A "Study" is a collection of series


Although we have groupings on the level of study, images will be generally moved around and processed on the level of Series. For high level overview, continue reading. For module and modality specific docs, see our [docs](docs) folder. If anything is missing documentation please [open an issue](https://www.github.com/pydicom/sendit)


## Configuration
The configuration for the application consists of the files in the [sendit/settings](sendit/settings) folder. The files that need attention are `secrets.py` and [config.py](sendit/settings/config.py).  First make your secrets.py like this:

```
cp sendit/settings/bogus_secrets.py sendit/settings/secrets.py
vim sendit/settings/secrets.py
```

Once you have your `secrets.py`, it needs the following added:

 - `SECRET_KEY`: Django will not run without one! You can generate one [here](http://www.miniwebtool.com/django-secret-key-generator/)
 - `DEBUG`: Make sure to set this to `False` for production.


For [config.py](sendit/settings/config.py) you should configure the following:

```
# If True, we will have the images first go to a task to retrieve fields to deidentify
DEIDENTIFY_RESTFUL=True
```

If this variable is False, we skip this task, and images are instead sent to the next task (or tasks) to send them to different storage. If True, the images are first put in the queue to be de-identified, and then upon receival of the identifiers, then they are put into the same queues to be sent to storage. These functions can be modified to use different endpoints, or do different replacements in the data:

 - The function `get_identifiers` under [main/tasks.py](sendit/apps/main/tasks.py) should take in a series ID, and use that series to look up images, and send a RESTful call to some API point to return fields to replace in the data. The JSON response should be saved to an `SeriesIdentifiers` object along with a pointer to the Series.
 - The function `replace_identifers` also under [main/tasks.py](sendit/apps/main/tasks.py) should then load this object, do whatever work is necessary for the data, and then put the data in the queue for storage.

You might want to tweak both of the above functions depending on your call endpoint, the response format (should be json as it goes into a jsonfield), and then how it is used to deidentify the data.


```
# We can turn on/off send to Orthanc. If turned off, the images would just be processed
SEND_TO_ORTHANC=True

# The ipaddress of the Orthanc server to send the finished dicoms (cloud PACS)
ORTHANC_IPADDRESS="127.0.0.1"

# The port of the same machine (by default they map it to 4747
ORTHAC_PORT=4747
```

Since the Orthanc is a server itself, if we are ever in need of a way to quickly deploy and bring down these intances as needed, we could do that too, and the application would retrieve the ipaddress programatically.

And I would (like) to eventually add the following, meaning that we also send datasets to Google Cloud Storage and Datastore, ideally in compressed nifti instead of dicom, and with some subset of fields. These functions are by default turned off.

```
# Should we send to Google at all?
SEND_TO_GOOGLE=False

# Google Cloud Storage and Datastore
GOOGLE_CLOUD_STORAGE='som-pacs'
```

Importantly, for the above, there must be a `GOOGLE_APPLICATION_CREDENTIALS` filepath exported in the environment, or it should be run on a Google Cloud Instance (unlikely).

## Authentication
If you look in [sendit/settings/auth.py](sendit/settings/auth.py) you will see something called `lockdown` and that it is turned on:

```
# Django Lockdown
LOCKDOWN_ENABLED=True
```

This basically means that the entire site is locked down, or protected for use (from a web browser) with a password. It's just a little extra layer of security. You can set the password by defining it in your [sendit/settings/secrets.py](sendit/settings/secrets.py):

```
LOCKDOWN_PASSWORDS = ('mysecretpassword',)
```


## Basic Pipeline
This application lives in a docker-compose application running on `STRIDE-HL71`.


### 1. Data Input
This initial setup is stupid in that it's going to be checking an input folder to find new images. We do this using the [watcher](sendit/apps/watcher) application, which is started and stopped with a manage.py command:

```
python manage.py watcher_start
python manage.py watcher_stop
```

And the default is to watch for files added to [data](data), which is mapped to '/data' in the container. This means that `STRIDE-HL71` will receive DICOM from somewhere. It should use an atomic download strategy, but with folders, into the application data input folder. This will mean that when it starts, the folder might look like:
 
 
```bash
/data
     ST-000001.tmp2343
         image1.dcm 
         image2.dcm 
         image3.dcm 

```
Only when all of the dicom files are finished copying will the driving function rename it to be like this:


```bash
/data
     ST-000001
         image1.dcm 
         image2.dcm 
         image3.dcm 

```

A directory is considered "finished" and ready for processing when it does **not** have an entension that starts with "tmp". For more details about the watcher daemon, you can look at [his docs](docs/watcher.md). While many examples are provided, for this application we use the celery task `import_dicomdir` in [main/tasks.py](sendit/apps/main/tasks.py) to read in a finished dicom directory from the directory being watched, and this uses the class `DicomCelery` in the [event_processors](sendit/apps/watcher/event_processors.py) file. Other examples are provided, in the case that you want to change or extend the watcher daemon.


### 2. Database Models
The Dockerized application will check the folder at some frequency (once a minute perhaps) and look for folders that are not in the process of being populated. When a folder is found:

 - A new object in the database is created to represent the "Series"
 - Each "Image" is represented by an equivalent object
 - Each "Image" is linked to its "Series", and if relevant, the "Series" is linked to a "Study."
 - Currently, all uids for each must be unique.


### 3. Retrive Identifiers
After these objects are created, we will generate a single call to a Restful service to get back a response that will have fields that need to be substituted in the data. For Stanford, we will use the DASHER API to get identifiers for the study. The call will be made, the response received, and the response itself saved to the database as a "SeriesIdentifiers" object. This object links to the Series it is intended for. The Series id will be put into a job queue for the final processing. This step will not be performed if 


### 3. Replacement of identifiers
The job queue will process datasets when the server has available resources. There will be likely 5 workers for a single application deployment. The worker will do the following:

 - receive a job from the queue with a series id
 - use the series ID to look up the identifiers, and all dicom images
 - for each image, prepare a new dataset that has been de-identified (this will happen in a temporary folder)
 - send the dataset to the cloud Orthanc, and (maybe also?) Datastore and Storage

Upon completion, we will want some level of cleanup of both the database, and the corresponding files. This application is not intended as some kind of archive for data, but a node that filters and passes along.


# Status States
In order to track status of images, we should have different status states. I've so far created a set for images, which also give information about the status of the series they belong to:

```
IMAGE_STATUS = (('NEW', 'The image was just added to the application.'),
               ('PROCESSING', 'The image is currently being processed, and has not been sent.'),
               ('DONEPROCESSING','The image is done processing, but has not been sent.'),
               ('SENT','The image has been sent, and verified received.'),
               ('DONE','The image has been received, and is ready for cleanup.'))
```

These can be tweaked as needed, and likely I will do this as I develop the application. I will want to add more / make things simpler. I'm not entirely sure where I want these to come in, but they will.


# Questions

- When there is error reading a dicom file (I am using "force" so this will read most dicom files, but will have a KeyError for a non dicom file) I am logging the error and moving on, without deleting the file. Is this the approach we want to take?
- I am assuming that the fields that are in the list given by Susan to de-identify, those are ones we want to save to DASHER as custom metadata (that aren't the obvious entity id, etc)? 
- Should the id_source be the "human friendly" name, or the entire SOPInstanceUID?
- The request to the identifiers (uid) endpoint has an entity, and then a list of items. The entity maps nicely to whatever individual is relevant for a series of images, but it isn't clear to me how I know what the id_source is for the data. I could either assume all are from Stanford and call it "Stanford MRN", or I could use the source of the images, which would be incorrect because it's from a machine.
 - What should we do if the dicom image doesn't have a PatientID (and thus we have no way to identify the patient?) Right now I'm skipping the image.
- For each item in a request, there is an `id_source` and the example is `GE PACS`. However, it's not clear if this is something that should come from the dicom data (or set by default by us, since we are pulling all from the same PACS) or if it should be one of the following (in the dicom header). Right now I am using `SOPInstanceUID`, but that isn't super human friendly.
- For the fields that we don't need to remove from the dicom images (eg, about the image data) I think it wouldn't be useful to have as `custom_fields`, so I am suggesting (and currently implementing) that we don't send it to dasher with each item. We can send these fields to datastore to be easily searched, if that functionality is wanted.
- I originally had the PatientID being used as the identifiers main id, but I think this should actually be AccessionNumber (and the PatientID represented in the custom_fields, because we don't even always have a patient, but we will have an accession number!) Right now I am using accession number, and I can change this if necessary.
