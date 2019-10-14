# 1Password to pass
This utility converts a complex 1Password database export into [pass](https://www.passwordstore.org/).

Because most pass importing tools often miss out on valuable data stored insite 1pif files, this program 
was created to extract everything in the conversion process. It takes an all-or-nothing approach, 
exporting all Sections and Fields, alsonside full support for OTPs [pass-opt](https://github.com/tadfisher/pass-otp).

## Preparing Data
This program requires you [export your data from the 1Password](https://support.1password.com/export/) desktop application 
in a compatible directory structure for import:

    EXPORT_DIR/$GROUP/
    EXPORT_DIR/$GROUP/{Cards|Notes|SSN|Wireless|Software|Logins|All} (.+)/data.1pif

This design allows you to export each of your Vaults, either with all data (All) or per each category. 
Please note that 1Password does *NOT* allow you to export files via 1pif, meaning you must manually 
take out all documents from your store before you can export to 1pif. Alternatively, only export the 
categories you need (Login, Cards, etc).  

**$GROUP** is used to identify the directory where the data will be added in pass. Recommend use something short and lowercase.

## Running Conversion
This tool uses python's asyncio to resolve the embarassingly parallel problem of running each import script.

Invoke a dry-run import using

    python3 1pwdbatch.py --dns --simulate -d EXPORT_DIR

Invoke a real import using (use --dns for reverse DNS naming)

    python3 1pwdbatch.py --dns -d EXPORT_DIR

## Imported Names
Data is imported into pass using the following syntax:

* Cards: slugify(title).CC
* Notes: slugify(title).XNOTE
* SSN: slugify(title).SSN
* Wireless: slugify(title).WIFI
* Software: slugify(title).SFT
* Logins: slugify(title) OR dns-naming

dns-syntax: (use --dns) defines reversed DNS as title. For example, a login for mail.google.com becomes com.google.mail
If there are any naming clashes within a single run, an ID is appended, e.g: com.google.mail13

### Open Source
Special thank you to:
* Tobias V. Langhoff: [1password2pass](https://github.com/tobiasvl/1password2pass)

Narcis M Pap, 2019.