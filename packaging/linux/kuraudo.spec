# ビルド済みの Flutter バイナリを詰めるだけなので、debuginfo 生成と strip 等の後処理はしない
%global debug_package %{nil}
%global __os_install_post %{nil}

Name:           kuraudo
Version:        @VERSION@
Release:        1%{?dist}
Summary:        Local-first password manager
License:        GPL-3.0-only
URL:            https://github.com/orgsonai/kuraudo
Source0:        %{name}-%{version}.tar.gz
Requires:       gtk3, libsecret

%description
Kuraudo stores an encrypted vault locally and supports optional synchronization.

%prep
%setup -q

%install
mkdir -p %{buildroot}
cp -a opt usr %{buildroot}/

%files
/opt/kuraudo
/usr/bin/kuraudo
/usr/share/applications/kuraudo.desktop
/usr/share/icons/hicolor/512x512/apps/kuraudo.png

%changelog
* Tue Aug 11 2026 Zero to Ship - @VERSION@-1
- Package Kuraudo for RPM-based distributions.
