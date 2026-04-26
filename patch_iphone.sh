#!/bin/bash
sed -i '' '4i\
#if os(iOS)
' file-explosion/ContentView+iPhone.swift
echo "#endif" >> file-explosion/ContentView+iPhone.swift
