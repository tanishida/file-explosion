#!/bin/bash
sed -i '' '3i\
#if os(iOS)
' file-explosion/ContentView+iPhone.swift
